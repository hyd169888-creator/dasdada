#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent(true)

#Include AI_Translate.ahk
#Include "*i FloatBar.ahk"

; ==============================================================================
; 注册底层键盘消息与系统关闭消息拦截
; ==============================================================================
OnMessage(0x0100, WM_KEYDOWN_ACCELERATOR, 2)
OnMessage(0x0010, WM_CLOSE_INTERCEPT, 2)

WM_KEYDOWN_ACCELERATOR(wParam, lParam, msg, hwnd) {
    static IID_IOleInPlaceActiveObject := "{00000117-0000-0000-C000-000000000046}"
    if (SettingsUI.wb && SettingsUI.gui && WinActive("ahk_id " . SettingsUI.gui.Hwnd)) {
        try {
            oleObj := ComObjQuery(SettingsUI.wb.Value, IID_IOleInPlaceActiveObject)
            if oleObj {
                tagMSG := Buffer(A_PtrSize == 8 ? 48 : 28, 0)
                NumPut("ptr", hwnd, tagMSG, 0)
                NumPut("uint", msg, tagMSG, A_PtrSize == 8 ? 8 : 4)
                NumPut("ptr", wParam, tagMSG, A_PtrSize == 8 ? 16 : 8)
                NumPut("ptr", lParam, tagMSG, A_PtrSize == 8 ? 24 : 12)
                NumPut("uint", A_TickCount, tagMSG, A_PtrSize == 8 ? 32 : 16)
                
                hr := ComCall(5, oleObj, "ptr", tagMSG.Ptr)
                if (hr == 0)
                    return 0
            }
        }
    }
}

WM_CLOSE_INTERCEPT(wParam, lParam, msg, hwnd) {
    if (SettingsUI.gui && hwnd == SettingsUI.gui.Hwnd) {
        SettingsUI.Hide()
        return 0
    }
}

class SettingsUI {
    static gui := 0
    static wb := 0
    static configFile := ""
    static configData := Map()
    static onHotkeysUpdatedCallback := 0
    static trayInitialized := false

    static InitBrowserEngine() {
        try {
            regPath := "HKEY_CURRENT_USER\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"
            RegWrite(11001, "REG_DWORD", regPath, "AutoHotkey64.exe")
            RegWrite(11001, "REG_DWORD", regPath, "AutoHotkey32.exe")
            SplitPath(A_ScriptFullPath, &exeName)
            RegWrite(11001, "REG_DWORD", regPath, exeName)
        }
    }

    ; ==========================================================================
    ; 获取最佳匹配的 ICO 图标绝对路径
    ; ==========================================================================
    static GetBestIcoPath() {
        icoDir := A_ScriptDir . "\assets\logo\"
        preferredList := [
            icoDir . "256x256.ico",
            icoDir . "48x48.ico",
            icoDir . "32x32.ico",
            icoDir . "app.ico",
            icoDir . "16x16.ico"
        ]
        for p in preferredList {
            if FileExist(p)
                return p
        }
        return ""
    }

    ; ==========================================================================
    ; Win32 原生 DPI 级别高精度图标渲染绑定
    ; ==========================================================================
    static ApplyNativeWindowIcons(hwnd) {
        icoPath := this.GetBestIcoPath()
        if (icoPath == "" || !hwnd)
            return

        smW := DllCall("GetSystemMetrics", "int", 49, "int")
        smH := DllCall("GetSystemMetrics", "int", 50, "int")
        lgW := DllCall("GetSystemMetrics", "int", 11, "int")
        lgH := DllCall("GetSystemMetrics", "int", 12, "int")

        hSmallIcon := DllCall("LoadImageW", "ptr", 0, "wstr", icoPath, "uint", 1, "int", smW, "int", smH, "uint", 0x0010, "ptr")
        hBigIcon   := DllCall("LoadImageW", "ptr", 0, "wstr", icoPath, "uint", 1, "int", lgW, "int", lgH, "uint", 0x0010, "ptr")

        if hSmallIcon
            SendMessage(0x80, 0, hSmallIcon, hwnd)
        if hBigIcon
            SendMessage(0x80, 1, hBigIcon, hwnd)
    }

    ; ==========================================================================
    ; 初始化系统托盘菜单（点击托盘默认打开设置中心）
    ; ==========================================================================
    static InitTrayMenu() {
        if (this.trayInitialized)
            return
        
        icoPath := this.GetBestIcoPath()
        if (icoPath != "") {
            try TraySetIcon(icoPath)
        }

        A_IconTip := "AI 智能打字翻译"
        tray := A_TrayMenu
        tray.Delete()
        
        tray.Add("⚙️ 打开设置中心", (*) => this.Show())
        tray.Add("🌐 打开翻译框", (*) => (IsSet(FloatBar) ? FloatBar.Show() : ""))
        tray.Add()
        tray.Add("❌ 退出", (*) => ExitApp())
        
        ; 默认左键单机动作设置为：打开设置中心
        tray.Default := "⚙️ 打开设置中心"
        tray.ClickCount := 1
        
        this.trayInitialized := true
    }

    ; ==========================================================================
    ; 动态遍历 assets\logo 目录，自动读取 PNG/JPG 并转为 Base64
    ; ==========================================================================
    static GetLogoBase64() {
        logoDir := A_ScriptDir . "\assets\logo\"
        targetPath := ""
        mime := "image/png"

        loop files, logoDir . "*.*" {
            ext := StrLower(A_LoopFileExt)
            if (ext == "png" || ext == "jpg" || ext == "jpeg") {
                if InStr(A_LoopFileName, "128") {
                    targetPath := A_LoopFileFullPath
                    mime := (ext == "png") ? "image/png" : "image/jpeg"
                    break
                }
            }
        }

        if (targetPath == "") {
            loop files, logoDir . "*.*" {
                ext := StrLower(A_LoopFileExt)
                if (ext == "png" || ext == "jpg" || ext == "jpeg") {
                    targetPath := A_LoopFileFullPath
                    mime := (ext == "png") ? "image/png" : "image/jpeg"
                    break
                }
            }
        }

        if (targetPath == "" || !FileExist(targetPath))
            return ""

        try {
            fileObj := FileOpen(targetPath, "r")
            fileLen := fileObj.Length
            fileBuf := Buffer(fileLen, 0)
            fileObj.RawRead(fileBuf, fileLen)
            fileObj.Close()

            charsNeeded := 0
            DllCall("Crypt32.dll\CryptBinaryToStringW", "ptr", fileBuf.Ptr, "uint", fileLen, "uint", 0x40000001, "ptr", 0, "uint*", &charsNeeded)
            outBuf := Buffer(charsNeeded * 2, 0)
            DllCall("Crypt32.dll\CryptBinaryToStringW", "ptr", fileBuf.Ptr, "uint", fileLen, "uint", 0x40000001, "ptr", outBuf.Ptr, "uint*", &charsNeeded)

            b64 := StrGet(outBuf)
            b64 := StrReplace(b64, "`r", "")
            b64 := StrReplace(b64, "`n", "")
            b64 := StrReplace(b64, " ", "")
            return "data:" . mime . ";base64," . b64
        } catch {
            return ""
        }
    }

    static Show() {
        this.InitTrayMenu()

        if (this.gui != 0) {
            this.gui.Show("w520 h740 Center")
            this.ApplyNativeWindowIcons(this.gui.Hwnd)
            this.SyncConfigToWeb()
            return
        }

        this.InitBrowserEngine()
        this.configFile := A_ScriptDir . "\config\setting.json"
        this.configData := this.LoadConfig()

        myGui := Gui("+AlwaysOnTop", "AI 智能打字翻译 - 设置中心")
        myGui.MarginX := 0
        myGui.MarginY := 0
        myGui.BackColor := "F5F6F2"

        this.wb := myGui.AddActiveX("x0 y0 w520 h740", "Shell.Explorer")
        this.wb.Value.Silent := true
        this.wb.Value.Navigate("about:blank")
        while this.wb.Value.ReadyState != 4
            Sleep(10)

        ; 获取 Base64 编码并注入占位符
        logoDataUri := this.GetLogoBase64()
        htmlCode := this.GetHTMLTemplate()
        if (logoDataUri != "") {
            imgTag := '<img src="' . logoDataUri . '" class="brand-avatar" alt="Logo" />'
        } else {
            imgTag := '<div class="brand-avatar" style="background:#18181B; display:inline-block;"></div>'
        }
        htmlCode := StrReplace(htmlCode, "{{LOGO_ELEMENT}}", imgTag)

        doc := this.wb.Value.Document
        doc.open()
        doc.write(htmlCode)
        doc.close()

        doc.parentWindow.ahk_call := (action, data) => this.HandleWebAction(action, data)

        this.gui := myGui
        myGui.OnEvent("Close", (guiObj) => (this.Hide(), true))
        myGui.OnEvent("Escape", (guiObj) => (this.Hide(), true))
        
        myGui.Show("w520 h740 Center")
        this.ApplyNativeWindowIcons(myGui.Hwnd)

        SetTimer(() => this.SyncConfigToWeb(), -50)
    }

    static Hide() {
        if (this.gui) {
            this.gui.Hide()
        }
    }

    static HandleWebAction(action, jsonPayloadStr) {
        if (action == "check") {
            baseUrl := RegExMatch(jsonPayloadStr, '"baseUrl"\s*:\s*"([^"]*)"', &u) ? u[1] : ""
            model := RegExMatch(jsonPayloadStr, '"model"\s*:\s*"([^"]*)"', &m) ? m[1] : ""
            apiKey := RegExMatch(jsonPayloadStr, '"apiKey"\s*:\s*"([^"]*)"', &k) ? k[1] : ""

            cfg := Map(
                "base_url", baseUrl,
                "model", model,
                "api_key", apiKey
            )
            res := AITranslator.ValidateAPI(cfg)
            this.wb.Value.Document.parentWindow.updateCheckStatus(res.valid ? 1 : 0, res.msg)
        } 
        else if (action == "save") {
            try {
                if !DirExist(A_ScriptDir . "\config")
                    DirCreate(A_ScriptDir . "\config")
                
                if FileExist(this.configFile)
                    FileDelete(this.configFile)
                FileAppend(jsonPayloadStr, this.configFile, "UTF-8")
                
                this.configData := this.LoadConfig()
                
                if (this.onHotkeysUpdatedCallback) {
                    this.onHotkeysUpdatedCallback.Call()
                }
            } catch as err {
                this.wb.Value.Document.parentWindow.showCenterToast("保存失败: " . err.Message, true)
            }
        }
    }

    static SyncConfigToWeb() {
        if !this.wb || !this.wb.Value
            return
        
        curr := this.configData.Has("current_provider") ? this.configData["current_provider"] : "DeepSeek"
        target := this.configData.Has("target_lang") ? this.configData["target_lang"] : "en"
        source := this.configData.Has("source_lang") ? this.configData["source_lang"] : "auto"
        
        jsonStr := AITranslator.MapToJSON(this.configData["providers"])
        hkJsonStr := AITranslator.MapToJSON(this.configData["hotkeys"])
        this.wb.Value.Document.parentWindow.initAllConfigs(curr, source, target, jsonStr, hkJsonStr)
    }

    static LoadConfig() {
        defaultMap := Map(
            "current_provider", "DeepSeek",
            "source_lang", "auto",
            "target_lang", "en",
            "providers", Map(
                "Gemini", Map("base_url", "https://generativelanguage.googleapis.com/v1beta/openai", "model", "gemini-1.5-flash", "api_key", ""),
                "OpenAI", Map("base_url", "https://api.openai.com/v1", "model", "gpt-4o-mini", "api_key", ""),
                "NVIDIA", Map("base_url", "https://integrate.api.nvidia.com/v1", "model", "meta/llama-3.1-8b-instruct", "api_key", ""),
                "DeepSeek", Map("base_url", "https://api.deepseek.com/v1", "model", "deepseek-chat", "api_key", ""),
                "Doubao", Map("base_url", "https://ark.cn-beijing.volces.com/api/v3", "model", "ep-xxxxxx", "api_key", ""),
                "Custom", Map("base_url", "https://tokenrhythm.studio/v1", "model", "deepseek-v4-flash", "api_key", "")
            ),
            "hotkeys", Map(
                "show_bar", "!y",
                "settings", "!s",
                "output_trans", "Enter",
                "output_raw", "^Enter",
                "switch_ai", "Tab"
            )
        )

        if !FileExist(this.configFile)
            return defaultMap
        
        try {
            content := FileRead(this.configFile, "UTF-8")
            if (RegExMatch(content, '"current_provider"\s*:\s*"([^"]+)"', &m))
                defaultMap["current_provider"] := m[1]
            if (RegExMatch(content, '"source_lang"\s*:\s*"([^"]+)"', &s))
                defaultMap["source_lang"] := s[1]
            if (RegExMatch(content, '"target_lang"\s*:\s*"([^"]+)"', &t))
                defaultMap["target_lang"] := t[1]

            for pName in ["Gemini", "OpenAI", "NVIDIA", "DeepSeek", "Doubao", "Custom"] {
                if RegExMatch(content, 's)"' . pName . '"\s*:\s*\{(.*?)\}', &block) {
                    bStr := block[1]
                    if RegExMatch(bStr, '"base_url"\s*:\s*"([^"]*)"', &u)
                        defaultMap["providers"][pName]["base_url"] := u[1]
                    if RegExMatch(bStr, '"model"\s*:\s*"([^"]*)"', &md)
                        defaultMap["providers"][pName]["model"] := md[1]
                    if RegExMatch(bStr, '"api_key"\s*:\s*"([^"]*)"', &k)
                        defaultMap["providers"][pName]["api_key"] := k[1]
                }
            }

            if RegExMatch(content, 's)"hotkeys"\s*:\s*\{(.*?)\}', &hkBlock) {
                hStr := hkBlock[1]
                for hkKey in ["show_bar", "settings", "output_trans", "output_raw", "switch_ai"] {
                    if RegExMatch(hStr, '"' . hkKey . '"\s*:\s*"([^"]*)"', &hVal)
                        defaultMap["hotkeys"][hkKey] := hVal[1]
                }
            }
        }
        return defaultMap
    }

    static GetHTMLTemplate() {
        return '
        (
        <!DOCTYPE html>
        <html>
        <head>
            <meta http-equiv="X-UA-Compatible" content="IE=edge" />
            <meta charset="utf-8" />
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; }
                html, body { width: 100%; height: 100%; overflow: hidden; background-color: #F5F6F2; color: #18181B; user-select: none; }
                .container { padding: 16px 22px; position: relative; height: 100%; }

                .header-bar { display: table; width: 100%; margin-bottom: 12px; }
                .brand-left { display: table-cell; vertical-align: middle; }
                
                /* 自适应圆角品牌 Logo */
                .brand-avatar { 
                    display: inline-block; 
                    width: 34px; 
                    height: 34px; 
                    border-radius: 8px; 
                    margin-right: 9px; 
                    vertical-align: middle; 
                    object-fit: contain;
                }
                
                .brand-title { display: inline-block; vertical-align: middle; }
                .brand-name { font-size: 13.5px; font-weight: 800; letter-spacing: 0.5px; color: #18181B; }
                .brand-sub { font-size: 11px; color: #71717A; }
                
                .pills-right { display: table-cell; vertical-align: middle; text-align: right; }
                .pill { display: inline-block; font-size: 12px; padding: 4px 13px; border-radius: 16px; color: #71717A; background: transparent; cursor: pointer; transition: all 0.2s; }
                .pill.active { background: #18181B; color: #FFFFFF; font-weight: 700; }

                .tag { font-size: 10.5px; font-weight: 800; letter-spacing: 0.8px; color: #6366F1; text-transform: uppercase; margin-bottom: 2px; }
                .main-title { font-size: 20px; font-weight: 900; line-height: 1.2; color: #18181B; margin-bottom: 3px; letter-spacing: -0.3px; }
                .sub-desc { font-size: 12px; color: #71717A; margin-bottom: 12px; }

                .card { 
                    background: #FFFFFF; 
                    border-radius: 14px; 
                    padding: 12px 16px; 
                    margin-bottom: 10px; 
                    border: 1px solid #E3E4DC; 
                    box-shadow: 0 1px 3px rgba(0,0,0,0.02);
                    position: relative;
                }
                .card-header { font-size: 11.5px; font-weight: 800; letter-spacing: 0.6px; color: #71717A; text-transform: uppercase; margin-bottom: 9px; }

                .form-row { display: table; width: 100%; margin-bottom: 9px; position: relative; }
                .form-row:last-child { margin-bottom: 0; }
                .form-label { display: table-cell; width: 105px; font-size: 13px; font-weight: 700; color: #3F3F46; vertical-align: middle; }
                .form-field { display: table-cell; vertical-align: middle; position: relative; }

                .input-box {
                    width: 100%;
                    height: 35px;
                    background-color: #F3F4EE !important;
                    border: 1.5px solid #84CC16 !important;
                    border-radius: 9px;
                    padding: 0 12px;
                    font-size: 13.5px;
                    color: #18181B;
                    outline: none;
                    box-shadow: none !important;
                }
                .input-box:focus, .input-box:hover {
                    background-color: #F3F4EE !important;
                    border: 1.5px solid #84CC16 !important;
                    outline: none;
                    box-shadow: none !important;
                }

                .hk-input {
                    font-weight: 700;
                    letter-spacing: 0.5px;
                    color: #15803D !important;
                    cursor: pointer;
                    text-align: left;
                }

                .custom-select {
                    position: relative;
                    width: 100%;
                    user-select: none;
                }
                
                .select-trigger {
                    width: 100%;
                    height: 35px;
                    background-color: #F3F4EE !important;
                    border: 1.5px solid #84CC16 !important;
                    border-radius: 9px;
                    padding: 0 12px;
                    font-size: 13.5px;
                    color: #18181B;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    cursor: pointer;
                    outline: none;
                    box-shadow: none !important;
                }
                .select-trigger:hover, .custom-select.open .select-trigger {
                    background-color: #F3F4EE !important;
                    border: 1.5px solid #84CC16 !important;
                }

                .select-text {
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    padding-right: 8px;
                }

                .select-arrow {
                    width: 14px;
                    height: 14px;
                    flex-shrink: 0;
                    fill: none;
                    stroke: #84CC16;
                    stroke-width: 2.4;
                    stroke-linecap: round;
                    stroke-linejoin: round;
                    transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1);
                }
                .custom-select.open .select-arrow {
                    transform: rotate(180deg);
                }

                .select-dropdown {
                    position: absolute;
                    top: calc(100% + 5px);
                    left: 0;
                    right: 0;
                    height: 180px;
                    background-color: #F3F4EE !important;
                    border: 1.5px solid #84CC16 !important;
                    border-radius: 11px;
                    box-shadow: 0 12px 30px rgba(0, 0, 0, 0.1), 0 4px 10px rgba(0, 0, 0, 0.04);
                    padding: 4px;
                    z-index: 10000;
                    overflow: hidden;
                    opacity: 0;
                    visibility: hidden;
                    transform: translateY(-6px) scale(0.98);
                    transition: opacity 0.2s cubic-bezier(0.16, 1, 0.3, 1), 
                                transform 0.2s cubic-bezier(0.16, 1, 0.3, 1), 
                                visibility 0.2s;
                    pointer-events: none;
                }

                .custom-select.open .select-dropdown {
                    opacity: 1;
                    visibility: visible;
                    transform: translateY(0) scale(1);
                    pointer-events: auto;
                }

                .select-scroll-viewport {
                    width: calc(100% + 22px);
                    height: 100%;
                    overflow-y: scroll;
                    overflow-x: hidden;
                    padding-right: 28px;
                    padding-left: 2px;
                    padding-top: 2px;
                    padding-bottom: 2px;
                    -ms-overflow-style: none;
                }
                .select-scroll-viewport::-webkit-scrollbar {
                    display: none;
                    width: 0;
                    height: 0;
                }

                .capsule-track {
                    position: absolute;
                    top: 5px;
                    bottom: 5px;
                    right: 6px;
                    width: 9px;
                    background-color: #D9DCD2;
                    border-radius: 9px;
                    pointer-events: none;
                    z-index: 10002;
                }

                .capsule-thumb {
                    position: absolute;
                    top: 0;
                    left: 1px;
                    width: 7px;
                    height: 36px;
                    background-color: #84CC16;
                    border-radius: 7px;
                    transition: top 0.06s ease-out;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.12);
                }

                .select-option {
                    padding: 7px 9px;
                    font-size: 13px;
                    color: #27272A;
                    border-radius: 7px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    transition: all 0.16s ease;
                    margin-bottom: 2px;
                }
                .select-option:last-child { margin-bottom: 0; }

                .select-option:hover {
                    background-color: #E5E7DC !important;
                    color: #000000;
                    transform: translateX(3px);
                }
                .select-option.selected {
                    background-color: #E2F6B8 !important;
                    color: #2D4A0C;
                    font-weight: 700;
                }

                .lime-card {
                    background: #D8FA63;
                    border-radius: 12px;
                    padding: 9px 13px;
                    margin-bottom: 12px;
                    border: 1px solid #C4EC44;
                    max-height: 70px;
                    overflow-y: auto;
                    box-sizing: border-box;
                }
                .lime-card::-webkit-scrollbar {
                    width: 4px;
                }
                .lime-card::-webkit-scrollbar-thumb {
                    background: rgba(0, 0, 0, 0.18);
                    border-radius: 4px;
                }
                
                .lime-tag { font-size: 10.5px; font-weight: 800; letter-spacing: 0.8px; color: #4D7C0F; text-transform: uppercase; margin-bottom: 2px; }
                .lime-text { font-size: 12px; font-weight: 700; color: #141416; word-break: break-all; line-height: 1.35; }

                .btn-row { display: table; width: 100%; }
                .btn-cell { display: table-cell; width: 50%; padding-right: 6px; }
                .btn-cell:last-child { padding-right: 0; padding-left: 6px; }
                
                .btn {
                    width: 100%;
                    height: 42px;
                    border-radius: 11px;
                    font-size: 13.5px;
                    font-weight: 800;
                    cursor: pointer;
                    border: none;
                    text-align: center;
                }
                .btn-dark { background: #18181B; color: #FFFFFF; }
                .btn-dark:hover { background: #27272A; }
                .btn-lime { background: #D8FA63; color: #18181B; border: 1px solid #C4EC44; }
                .btn-lime:hover { background: #C8EA2D; }

                #centerModalToast {
                    position: fixed;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    -webkit-transform: translate(-50%, -50%);
                    width: 270px;
                    background: rgba(24, 24, 27, 0.82);
                    -webkit-backdrop-filter: blur(16px);
                    backdrop-filter: blur(16px);
                    color: #FFFFFF;
                    padding: 22px 18px;
                    border-radius: 18px;
                    text-align: center;
                    display: none;
                    z-index: 999999;
                    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35), 0 0 0 1px rgba(255, 255, 255, 0.12) inset;
                    border: 1px solid rgba(255, 255, 255, 0.08);
                }
                .toast-icon {
                    width: 38px;
                    height: 38px;
                    line-height: 38px;
                    background: #D8FA63;
                    color: #18181B;
                    border-radius: 50%;
                    font-size: 20px;
                    font-weight: 900;
                    margin: 0 auto 10px auto;
                    box-shadow: 0 4px 12px rgba(216, 250, 99, 0.35);
                }
                .toast-title {
                    font-size: 14.5px;
                    font-weight: 800;
                    color: #FFFFFF;
                    margin-bottom: 4px;
                    letter-spacing: 0.3px;
                }
                .toast-desc {
                    font-size: 11.5px;
                    color: rgba(255, 255, 255, 0.75);
                }

                .page-section { display: none; }
                .page-section.active { display: block; }
            </style>
        </head>
        <body>
            <div id="centerModalToast">
                <div class="toast-icon" id="toastIcon">✓</div>
                <div class="toast-title" id="toastTitle">配置保存成功</div>
                <div class="toast-desc" id="toastDesc">全部配置已生效，可直接开始翻译</div>
            </div>

            <div class="container">
                <div class="header-bar">
                    <div class="brand-left">
                        {{LOGO_ELEMENT}}
                        <div class="brand-title">
                            <div class="brand-name">AI TRANSLATOR</div>
                            <div class="brand-sub">with Live Brain</div>
                        </div>
                    </div>
                    <div class="pills-right">
                        <div class="pill active" id="tabEngine" onclick="switchTab('engine')">实时引擎</div>
                        <div class="pill" id="tabHotkey" onclick="switchTab('hotkey')">快捷键</div>
                    </div>
                </div>

                <!-- 页面 1: 实时引擎设置 -->
                <div class="page-section active" id="pageEngine">
                    <div class="tag">LIVE INTELLIGENT TRANSLATION</div>
                    <div class="main-title">打字翻译，在每一次思考后生成</div>
                    <div class="sub-desc">连接大模型大脑，自动识别中外文并地道转化输出。</div>

                    <div class="card" id="cardLang" style="z-index: 50;">
                        <div class="card-header">Language Preference · 语言设定</div>
                        
                        <div class="form-row" style="z-index: 52;">
                            <div class="form-label">源语言</div>
                            <div class="form-field">
                                <div class="custom-select" id="select-sourceLang" data-value="auto">
                                    <div class="select-trigger" onclick="toggleDropdown('select-sourceLang')">
                                        <span class="select-text">自动识别 (中英双向智能互译)</span>
                                        <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>
                                    </div>
                                    <div class="select-dropdown">
                                        <div class="capsule-track"><div class="capsule-thumb" id="thumb-sourceLang"></div></div>
                                        <div class="select-scroll-viewport" onscroll="updateScroll('select-sourceLang', 'thumb-sourceLang')">
                                            <div class="select-option selected" data-value="auto" onclick="selectOption('select-sourceLang', 'auto', '自动识别 (中英双向智能互译)')">自动识别 (中英双向智能互译)</div>
                                            <div class="select-option" data-value="zh" onclick="selectOption('select-sourceLang', 'zh', '中文 (Chinese)')">中文 (Chinese)</div>
                                            <div class="select-option" data-value="en" onclick="selectOption('select-sourceLang', 'en', 'English (英语)')">English (英语)</div>
                                            <div class="select-option" data-value="ja" onclick="selectOption('select-sourceLang', 'ja', '日本語 (Japanese)')">日本語 (Japanese)</div>
                                            <div class="select-option" data-value="ko" onclick="selectOption('select-sourceLang', 'ko', '한국어 (Korean)')">한국어 (Korean)</div>
                                            <div class="select-option" data-value="es" onclick="selectOption('select-sourceLang', 'es', 'Español (西班牙语)')">Español (西班牙语)</div>
                                            <div class="select-option" data-value="fr" onclick="selectOption('select-sourceLang', 'fr', 'Français (法语)')">Français (法语)</div>
                                            <div class="select-option" data-value="de" onclick="selectOption('select-sourceLang', 'de', 'Deutsch (德语)')">Deutsch (德语)</div>
                                            <div class="select-option" data-value="ru" onclick="selectOption('select-sourceLang', 'ru', 'Русский (俄语)')">Русский (俄语)</div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="form-row" style="z-index: 51;">
                            <div class="form-label">目标语言</div>
                            <div class="form-field">
                                <div class="custom-select" id="select-targetLang" data-value="en">
                                    <div class="select-trigger" onclick="toggleDropdown('select-targetLang')">
                                        <span class="select-text">English (英语)</span>
                                        <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>
                                    </div>
                                    <div class="select-dropdown">
                                        <div class="capsule-track"><div class="capsule-thumb" id="thumb-targetLang"></div></div>
                                        <div class="select-scroll-viewport" onscroll="updateScroll('select-targetLang', 'thumb-targetLang')">
                                            <div class="select-option selected" data-value="en" onclick="selectOption('select-targetLang', 'en', 'English (英语)')">English (英语)</div>
                                            <div class="select-option" data-value="zh" onclick="selectOption('select-targetLang', 'zh', '中文 (Chinese)')">中文 (Chinese)</div>
                                            <div class="select-option" data-value="ja" onclick="selectOption('select-targetLang', 'ja', '日本語 (日语)')">日本語 (日语)</div>
                                            <div class="select-option" data-value="ko" onclick="selectOption('ko', '한국어 (韩语)')">한국어 (韩语)</div>
                                            <div class="select-option" data-value="es" onclick="selectOption('select-targetLang', 'es', 'Español (西班牙语)')">Español (西班牙语)</div>
                                            <div class="select-option" data-value="fr" onclick="selectOption('select-targetLang', 'fr', 'Français (法语)')">Français (法语)</div>
                                            <div class="select-option" data-value="de" onclick="selectOption('select-targetLang', 'de', 'Deutsch (德语)')">Deutsch (德语)</div>
                                            <div class="select-option" data-value="ru" onclick="selectOption('select-targetLang', 'ru', 'Русский (俄语)')">Русский (俄语)</div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="card" id="cardModel" style="z-index: 40;">
                        <div class="card-header">AI Engine & Endpoint · 大模型配置</div>
                        
                        <div class="form-row" style="z-index: 41;">
                            <div class="form-label">AI 平台</div>
                            <div class="form-field">
                                <div class="custom-select" id="select-provider" data-value="DeepSeek">
                                    <div class="select-trigger" onclick="toggleDropdown('select-provider')">
                                        <span class="select-text">DeepSeek（官方直连·深度思考）</span>
                                        <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>
                                    </div>
                                    <div class="select-dropdown">
                                        <div class="capsule-track"><div class="capsule-thumb" id="thumb-provider"></div></div>
                                        <div class="select-scroll-viewport" onscroll="updateScroll('select-provider', 'thumb-provider')">
                                            <div class="select-option" data-value="Gemini" onclick="selectOption('select-provider', 'Gemini', 'Gemini（需魔法）')">Gemini（需魔法）</div>
                                            <div class="select-option" data-value="OpenAI" onclick="selectOption('select-provider', 'OpenAI', 'ChatGPT（需魔法）')">ChatGPT（需魔法）</div>
                                            <div class="select-option" data-value="NVIDIA" onclick="selectOption('select-provider', 'NVIDIA', 'NVIDIA·免费满血模型（需魔法）')">NVIDIA·免费满血模型（需魔法）</div>
                                            <div class="select-option selected" data-value="DeepSeek" onclick="selectOption('select-provider', 'DeepSeek', 'DeepSeek（官方直连·深度思考）')">DeepSeek（官方直连·深度思考）</div>
                                            <div class="select-option" data-value="Qwen" onclick="selectOption('select-provider', 'Qwen', '通义千问 (阿里百炼·国内直连)')">通义千问 (阿里百炼·国内直连)</div>
                                            <div class="select-option" data-value="Doubao" onclick="selectOption('select-provider', 'Doubao', '豆包(ByteDance)')">豆包(ByteDance)</div>
                                            <div class="select-option" data-value="Custom" onclick="selectOption('select-provider', 'Custom', '自定义API(OpenAI 协议兼容）')">自定义API(OpenAI 协议兼容）</div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="form-row">
                            <div class="form-label">Base URL</div>
                            <div class="form-field">
                                <input type="text" id="baseUrl" class="input-box" placeholder="https://api.deepseek.com/v1" />
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-label">Model Name</div>
                            <div class="form-field">
                                <input type="text" id="modelName" class="input-box" placeholder="deepseek-chat" />
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-label">API Key</div>
                            <div class="form-field">
                                <input type="password" id="apiKey" class="input-box" placeholder="sk-xxxxxxxxxxxxxxxxxxxxxxxx" />
                            </div>
                        </div>
                    </div>

                    <div class="lime-card" id="statusCard">
                        <div class="lime-tag">System Status · 状态反馈</div>
                        <div class="lime-text" id="statusText">💡 准备就绪，可点击下方按钮发起连通性探针测试。</div>
                    </div>

                    <div class="btn-row">
                        <div class="btn-cell">
                            <button class="btn btn-dark" onclick="triggerCheck()">🚀 检测 API 有效性</button>
                        </div>
                        <div class="btn-cell">
                            <button class="btn btn-lime" onclick="triggerSave()">💾 保存并生效</button>
                        </div>
                    </div>
                </div>

                <!-- 页面 2: 快捷键设置 -->
                <div class="page-section" id="pageHotkey">
                    <div class="tag">SHORTCUT PREFERENCES</div>
                    <div class="main-title">全局交互快捷键管理</div>
                    <div class="sub-desc">支持自定义全局唤出、操作确认与快速模型轮换按键。</div>

                    <div class="card">
                        <div class="card-header">Global Shortcuts · 触发按键</div>
                        
                        <div class="form-row">
                            <div class="form-label">唤出悬浮翻译</div>
                            <div class="form-field">
                                <input type="text" id="hk_show_bar" class="input-box hk-input" onkeydown="recordHotkey(event, this)" placeholder="如: Alt+Y" />
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-label">打开设置中心</div>
                            <div class="form-field">
                                <input type="text" id="hk_settings" class="input-box hk-input" onkeydown="recordHotkey(event, this)" placeholder="如: Alt+S" />
                            </div>
                        </div>
                    </div>

                    <div class="card">
                        <div class="card-header">Window Actions · 悬浮窗内控制</div>
                        
                        <div class="form-row">
                            <div class="form-label">输出翻译结果</div>
                            <div class="form-field">
                                <input type="text" id="hk_output_trans" class="input-box hk-input" onkeydown="recordHotkey(event, this)" placeholder="如: Enter" />
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-label">输出原始文本</div>
                            <div class="form-field">
                                <input type="text" id="hk_output_raw" class="input-box hk-input" onkeydown="recordHotkey(event, this)" placeholder="如: Ctrl+Enter" />
                            </div>
                        </div>
                        <div class="form-row">
                            <div class="form-label">快速轮换模型</div>
                            <div class="form-field">
                                <input type="text" id="hk_switch_ai" class="input-box hk-input" onkeydown="recordHotkey(event, this)" placeholder="如: Tab" />
                            </div>
                        </div>
                    </div>

                    <div class="lime-card">
                        <div class="lime-tag">Tips · 按键提示</div>
                        <div class="lime-text">💡 点击输入框后直接按下组合键即可自动捕获，支持 Ctrl、Alt、Shift 及常用按键组合。</div>
                    </div>

                    <div class="btn-row">
                        <div class="btn-cell">
                            <button class="btn btn-dark" onclick="resetDefaultHotkeys()">🔄 恢复默认快捷键</button>
                        </div>
                        <div class="btn-cell">
                            <button class="btn btn-lime" onclick="triggerSave()">💾 保存快捷键</button>
                        </div>
                    </div>
                </div>
            </div>

            <script>
                var g_currentProvider = "DeepSeek";
                var g_allConfigs = {
                    "Gemini": { base_url: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-1.5-flash", api_key: "" },
                    "OpenAI": { base_url: "https://api.openai.com/v1", model: "gpt-4o-mini", api_key: "" },
                    "NVIDIA": { base_url: "https://integrate.api.nvidia.com/v1", model: "meta/llama-3.1-8b-instruct", api_key: "" },
                    "Qwen": { base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", api_key: "" },
                    "DeepSeek": { base_url: "https://api.deepseek.com/v1", model: "deepseek-chat", api_key: "" },
                    "Doubao": { base_url: "https://ark.cn-beijing.volces.com/api/v3", model: "ep-xxxxxx", api_key: "" },
                    "Custom": { base_url: "https://tokenrhythm.studio/v1", model: "deepseek-v4-flash", api_key: "" }
                };

                var g_hotkeys = {
                    show_bar: "!y",
                    settings: "!s",
                    output_trans: "Enter",
                    output_raw: "^Enter",
                    switch_ai: "Tab"
                };

                var toastTimer = null;

                function switchTab(tabName) {
                    var tabEngine = document.getElementById("tabEngine");
                    var tabHotkey = document.getElementById("tabHotkey");
                    var pageEngine = document.getElementById("pageEngine");
                    var pageHotkey = document.getElementById("pageHotkey");

                    if (tabName === "engine") {
                        tabEngine.className = "pill active";
                        tabHotkey.className = "pill";
                        pageEngine.className = "page-section active";
                        pageHotkey.className = "page-section";
                    } else {
                        tabEngine.className = "pill";
                        tabHotkey.className = "pill active";
                        pageEngine.className = "page-section";
                        pageHotkey.className = "page-section active";
                    }
                }

                function ahkToUser(str) {
                    if (!str) return "";
                    var res = "";
                    if (str.indexOf("#") !== -1) res += "Win+";
                    if (str.indexOf("^") !== -1) res += "Ctrl+";
                    if (str.indexOf("!") !== -1) res += "Alt+";
                    if (str.indexOf("+") !== -1) res += "Shift+";
                    var key = str.replace(/[#^!+]/g, "").toUpperCase();
                    return res + key;
                }

                function userToAhk(str) {
                    if (!str) return "";
                    var s = str.trim();
                    var parts = s.split("+");
                    var prefix = "";
                    var mainKey = "";
                    for (var i = 0; i < parts.length; i++) {
                        var p = parts[i].trim();
                        var lower = p.toLowerCase();
                        if (lower === "ctrl" || lower === "control") prefix += "^";
                        else if (lower === "alt") prefix += "!";
                        else if (lower === "shift") prefix += "+";
                        else if (lower === "win") prefix += "#";
                        else mainKey = p;
                    }
                    if (mainKey.length === 1) mainKey = mainKey.toLowerCase();
                    return prefix + mainKey;
                }

                function recordHotkey(e, inputEl) {
                    e.preventDefault();
                    var key = e.key || "";
                    if (["Control", "Alt", "Shift", "Meta"].indexOf(key) !== -1) {
                        return;
                    }
                    var parts = [];
                    if (e.ctrlKey) parts.push("Ctrl");
                    if (e.altKey) parts.push("Alt");
                    if (e.shiftKey) parts.push("Shift");
                    if (e.metaKey) parts.push("Win");

                    var keyName = key.length === 1 ? key.toUpperCase() : key;
                    if (keyName === " ") keyName = "Space";
                    parts.push(keyName);

                    inputEl.value = parts.join("+");
                }

                function resetDefaultHotkeys() {
                    document.getElementById("hk_show_bar").value = "Alt+Y";
                    document.getElementById("hk_settings").value = "Alt+S";
                    document.getElementById("hk_output_trans").value = "Enter";
                    document.getElementById("hk_output_raw").value = "Ctrl+Enter";
                    document.getElementById("hk_switch_ai").value = "Tab";
                    showCenterToast("已恢复默认快捷键，点击保存生效", false);
                }

                function updateScroll(selectId, thumbId) {
                    var selectEl = document.getElementById(selectId);
                    var viewport = selectEl.querySelector(".select-scroll-viewport");
                    var thumb = document.getElementById(thumbId);
                    
                    var scrollHeight = viewport.scrollHeight - viewport.clientHeight;
                    if (scrollHeight <= 0) {
                        thumb.style.display = "none";
                        return;
                    }
                    thumb.style.display = "block";

                    var maxThumbTravel = 168 - 36;
                    var progress = viewport.scrollTop / scrollHeight;
                    thumb.style.top = (progress * maxThumbTravel) + "px";
                }

                function toggleDropdown(selectId) {
                    var el = document.getElementById(selectId);
                    var isOpen = el.classList.contains("open");
                    closeAllDropdowns();
                    if (!isOpen) {
                        el.classList.add("open");
                        var thumbId = selectId.replace("select-", "thumb-");
                        setTimeout(function() { updateScroll(selectId, thumbId); }, 20);
                    }
                }

                function closeAllDropdowns() {
                    var selects = document.querySelectorAll(".custom-select");
                    for (var i = 0; i < selects.length; i++) {
                        selects[i].classList.remove("open");
                    }
                }

                document.addEventListener("click", function(e) {
                    if (!e.target.closest(".custom-select")) {
                        closeAllDropdowns();
                    }
                });

                function selectOption(selectId, value, labelText) {
                    var el = document.getElementById(selectId);
                    el.setAttribute("data-value", value);
                    el.querySelector(".select-text").innerText = labelText;
                    
                    var options = el.querySelectorAll(".select-option");
                    for (var i = 0; i < options.length; i++) {
                        if (options[i].getAttribute("data-value") === value) {
                            options[i].classList.add("selected");
                        } else {
                            options[i].classList.remove("selected");
                        }
                    }
                    
                    el.classList.remove("open");

                    if (selectId === "select-provider") {
                        onProviderChange(value);
                    }
                }

                function setCustomSelectValue(selectId, value) {
                    var el = document.getElementById(selectId);
                    if (!el) return;
                    var options = el.querySelectorAll(".select-option");
                    for (var i = 0; i < options.length; i++) {
                        if (options[i].getAttribute("data-value") === value) {
                            el.setAttribute("data-value", value);
                            el.querySelector(".select-text").innerText = options[i].innerText;
                            options[i].classList.add("selected");
                        } else {
                            options[i].classList.remove("selected");
                        }
                    }
                }

                function getCustomSelectValue(selectId) {
                    var el = document.getElementById(selectId);
                    return el ? (el.getAttribute("data-value") || "") : "";
                }

                function initAllConfigs(currProvider, sourceLang, targetLang, jsonConfigStr, hkJsonStr) {
                    try {
                        var parsed = (new Function("return " + jsonConfigStr))();
                        for (var k in parsed) {
                            if (parsed.hasOwnProperty(k)) {
                                g_allConfigs[k] = parsed[k];
                            }
                        }
                    } catch(e) {}

                    try {
                        if (hkJsonStr) {
                            var parsedHk = (new Function("return " + hkJsonStr))();
                            for (var hk in parsedHk) {
                                if (parsedHk.hasOwnProperty(hk)) {
                                    g_hotkeys[hk] = parsedHk[hk];
                                }
                            }
                        }
                    } catch(e) {}

                    g_currentProvider = currProvider;
                    setCustomSelectValue("select-provider", currProvider);
                    setCustomSelectValue("select-sourceLang", sourceLang);
                    setCustomSelectValue("select-targetLang", targetLang);

                    renderCurrentForm();
                    renderHotkeyForm();
                }

                function renderCurrentForm() {
                    var cfg = g_allConfigs[g_currentProvider] || {};
                    document.getElementById("baseUrl").value = cfg.base_url || "";
                    document.getElementById("modelName").value = cfg.model || "";
                    document.getElementById("apiKey").value = cfg.api_key || "";
                }

                function renderHotkeyForm() {
                    document.getElementById("hk_show_bar").value = ahkToUser(g_hotkeys.show_bar || "!y");
                    document.getElementById("hk_settings").value = ahkToUser(g_hotkeys.settings || "!s");
                    document.getElementById("hk_output_trans").value = ahkToUser(g_hotkeys.output_trans || "Enter");
                    document.getElementById("hk_output_raw").value = ahkToUser(g_hotkeys.output_raw || "^Enter");
                    document.getElementById("hk_switch_ai").value = ahkToUser(g_hotkeys.switch_ai || "Tab");
                }

                function onProviderChange(newProvider) {
                    g_allConfigs[g_currentProvider] = {
                        base_url: document.getElementById("baseUrl").value,
                        model: document.getElementById("modelName").value,
                        api_key: document.getElementById("apiKey").value
                    };

                    g_currentProvider = newProvider;
                    renderCurrentForm();

                    updateStatusText("已切换至「" + newProvider + "」，专属配置已自动载入。");
                }

                function triggerCheck() {
                    updateStatusText("⏳ 正在发送测速探针，请稍候...");
                    var payload = {
                        provider: getCustomSelectValue("select-provider"),
                        baseUrl: document.getElementById("baseUrl").value,
                        model: document.getElementById("modelName").value,
                        apiKey: document.getElementById("apiKey").value
                    };
                    window.ahk_call("check", JSON.stringify(payload));
                }

                function triggerSave() {
                    g_allConfigs[g_currentProvider] = {
                        base_url: document.getElementById("baseUrl").value,
                        model: document.getElementById("modelName").value,
                        api_key: document.getElementById("apiKey").value
                    };

                    var currentHotkeys = {
                        show_bar: userToAhk(document.getElementById("hk_show_bar").value) || "!y",
                        settings: userToAhk(document.getElementById("hk_settings").value) || "!s",
                        output_trans: userToAhk(document.getElementById("hk_output_trans").value) || "Enter",
                        output_raw: userToAhk(document.getElementById("hk_output_raw").value) || "^Enter",
                        switch_ai: userToAhk(document.getElementById("hk_switch_ai").value) || "Tab"
                    };

                    var fullConfigObj = {
                        current_provider: g_currentProvider,
                        source_lang: getCustomSelectValue("select-sourceLang"),
                        target_lang: getCustomSelectValue("select-targetLang"),
                        providers: g_allConfigs,
                        hotkeys: currentHotkeys
                    };

                    showCenterToast("全部配置已生效，快捷键已同步更新", false);
                    window.ahk_call("save", JSON.stringify(fullConfigObj));
                }

                function updateCheckStatus(success, msg) {
                    var card = document.getElementById("statusCard");
                    var txt = document.getElementById("statusText");
                    if (success === 1) {
                        card.style.background = "#D8FA63";
                        card.style.borderColor = "#C4EC44";
                        txt.style.color = "#15803D";
                        txt.innerHTML = "<b>" + msg + "</b>";
                    } else {
                        card.style.background = "#FEE2E2";
                        card.style.borderColor = "#FCA5A5";
                        txt.style.color = "#B91C1C";
                        txt.innerHTML = "<b>" + msg + "</b>";
                    }
                    card.scrollTop = 0;
                }

                function updateStatusText(text) {
                    var card = document.getElementById("statusCard");
                    var txt = document.getElementById("statusText");
                    card.style.background = "#D8FA63";
                    card.style.borderColor = "#C4EC44";
                    txt.style.color = "#141416";
                    txt.innerHTML = text;
                    card.scrollTop = 0;
                }

                function showCenterToast(msg, isError) {
                    var modal = document.getElementById("centerModalToast");
                    var icon = document.getElementById("toastIcon");
                    var title = document.getElementById("toastTitle");
                    var desc = document.getElementById("toastDesc");

                    if (toastTimer) {
                        clearTimeout(toastTimer);
                    }

                    if (isError) {
                        icon.innerText = "✕";
                        icon.style.background = "#EF4444";
                        icon.style.color = "#FFFFFF";
                        icon.style.boxShadow = "0 4px 12px rgba(239, 68, 68, 0.35)";
                        title.innerText = "保存失败";
                        desc.innerText = msg;
                    } else {
                        icon.innerText = "✓";
                        icon.style.background = "#D8FA63";
                        icon.style.color = "#18181B";
                        icon.style.boxShadow = "0 4px 12px rgba(216, 250, 99, 0.35)";
                        title.innerText = "配置保存成功";
                        desc.innerText = msg;
                    }

                    modal.style.display = "block";

                    toastTimer = setTimeout(function() {
                        modal.style.display = "none";
                    }, 3000);
                }
            </script>
        </body>
        </html>
        )'
    }
}