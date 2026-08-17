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
        
        tray.Default := "⚙️ 打开设置中心"
        tray.ClickCount := 1
        
        this.trayInitialized := true
    }

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
            this.gui.Show("w520 h790 Center")
            WinSetAlwaysOnTop(0, "ahk_id " . this.gui.Hwnd)
            this.ApplyNativeWindowIcons(this.gui.Hwnd)
            this.SyncConfigToWeb()
            return
        }

        this.InitBrowserEngine()
        this.configFile := A_ScriptDir . "\config\setting.json"
        this.configData := this.LoadConfig()

        myGui := Gui("-AlwaysOnTop", "AI 智能打字翻译 - 设置中心")
        myGui.MarginX := 0
        myGui.MarginY := 0
        myGui.BackColor := "F5F6F2"
        this.wb := myGui.AddActiveX("x0 y0 w520 h790", "Shell.Explorer")
    
        this.wb.Value.Silent := true
        this.wb.Value.Navigate("about:blank")
        while this.wb.Value.ReadyState != 4
            Sleep(10)

        logoDataUri := this.GetLogoBase64()
        htmlCode := this.GetHTMLTemplate()
        if (logoDataUri != "") {
            imgTag := '<img src="' . logoDataUri . '" class="brand-avatar" alt="Logo" />'
        } else {
            imgTag := '<div class="brand-avatar" style="background:#18181B; display:inline-block;"></div>'
        }
        htmlCode := StrReplace(htmlCode, "{{LOGO_ELEMENT}}", imgTag)
        
        verText := "v2.0.2"
        try {
            if IsSet(AppUpdater)
                verText := "v" . AppUpdater.GetCurrentVersion()
        }
        htmlCode := StrReplace(htmlCode, "{{APP_VERSION}}", verText)
        
        doc := this.wb.Value.Document
        doc.open()
        doc.write(htmlCode)
        doc.close()

        doc.parentWindow.ahk_call := (action, data) => this.HandleWebAction(action, data)

        this.gui := myGui
        myGui.OnEvent("Close", (guiObj) => (this.Hide(), true))
        myGui.OnEvent("Escape", (guiObj) => (this.Hide(), true))

        myGui.Show("w520 h790 Center")
        WinSetAlwaysOnTop(0, "ahk_id " . myGui.Hwnd)
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
            SetTimer(() => this.AsyncDoCheck(jsonPayloadStr), -10)
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

    static AsyncDoCheck(jsonPayloadStr) {
        try {
            provider := RegExMatch(jsonPayloadStr, '"provider"\s*:\s*"([^"]*)"', &p) ? p[1] : ""
            baseUrl  := RegExMatch(jsonPayloadStr, '"baseUrl"\s*:\s*"([^"]*)"', &u) ? u[1] : ""
            model    := RegExMatch(jsonPayloadStr, '"model"\s*:\s*"([^"]*)"', &m) ? m[1] : ""
            apiKey   := RegExMatch(jsonPayloadStr, '"apiKey"\s*:\s*"([^"]*)"', &k) ? k[1] : ""

            res := this.TestConnection(provider, baseUrl, model, apiKey)
            this.wb.Value.Document.parentWindow.updateCheckStatus(res.valid ? 1 : 0, res.msg)
        } catch as err {
            this.wb.Value.Document.parentWindow.updateCheckStatus(0, "检测异常: " . err.Message)
        }
    }

    static TestConnection(provider, baseUrl, model, apiKey) {
        if (apiKey == "")
            return { valid: 0, msg: "API Key 不能为空！" }

        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(4000, 4000, 7000, 7000)

        cleanUrl := RTrim(baseUrl, "/")
        startTime := A_TickCount

        try {
            if InStr(provider, "Gemini") && !InStr(cleanUrl, "openai") {
                if (!InStr(cleanUrl, "v1beta") && !InStr(cleanUrl, "v1"))
                    cleanUrl .= "/v1beta"
                
                fullUrl := cleanUrl . "/models/" . model . ":generateContent?key=" . apiKey
                body := '{"contents":[{"parts":[{"text":"ping"}]}]}'

                req.Open("POST", fullUrl, false)
                req.SetRequestHeader("Content-Type", "application/json; charset=UTF-8")
                req.Send(body)
            } else {
                if (!InStr(cleanUrl, "/chat/completions"))
                    cleanUrl .= "/chat/completions"

                body := '{"model":"' . model . '","messages":[{"role":"user","content":"ping"}],"max_tokens":5}'

                req.Open("POST", cleanUrl, false)
                req.SetRequestHeader("Content-Type", "application/json; charset=UTF-8")
                req.SetRequestHeader("Authorization", "Bearer " . apiKey)
                req.Send(body)
            }

            latency := A_TickCount - startTime
            status := req.Status

            if (status == 200) {
                return { valid: 1, msg: "✓ 连通性测试通过！ 响应正常 (" . latency . " ms)" }
            } else {
                return { valid: 0, msg: "❌ 接口返回 HTTP " . status . " (" . latency . " ms): " . SubStr(req.ResponseText, 1, 80) }
            }
        } catch as err {
            latency := A_TickCount - startTime
            return { valid: 0, msg: "❌ 网络超时或失败 (" . latency . " ms): " . err.Message }
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
        try {
            this.wb.Value.Document.parentWindow.initAllConfigs(curr, source, target, jsonStr, hkJsonStr)
        }
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
                "Qwen", Map("base_url", "https://dashscope.aliyuncs.com/compatible-mode/v1", "model", "qwen-plus", "api_key", ""),
                "DeepSeek", Map("base_url", "https://api.deepseek.com/v1", "model", "deepseek-chat", "api_key", ""),
                "Doubao", Map("base_url", "https://ark.cn-beijing.volces.com/api/v3", "model", "ep-xxxxxx", "api_key", ""),
                "Custom", Map("base_url", "https://tokenrhythm.studio/v1", "model", "deepseek-v4-flash", "api_key", "", "is_custom", true, "custom_name", "自定义API(默认)")
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

            ; 读取所有 Provider (双向兼容 custom_name 与 platform_nickname)
            if RegExMatch(content, 's)"providers"\s*:\s*\{(.*)\}\s*,\s*"hotkeys"', &pBlock) {
                pContent := pBlock[1]
                pos := 1
                while (pos := RegExMatch(pContent, '"([^"]+)"\s*:\s*\{([^}]*)\}', &mMatch, pos)) {
                    pKey := mMatch[1]
                    bStr := mMatch[2]
                    
                    bUrl := RegExMatch(bStr, '"base_url"\s*:\s*"([^"]*)"', &u) ? u[1] : ""
                    bModel := RegExMatch(bStr, '"model"\s*:\s*"([^"]*)"', &md) ? md[1] : ""
                    bKey := RegExMatch(bStr, '"api_key"\s*:\s*"([^"]*)"', &k) ? k[1] : ""
                    bIsCustom := InStr(bStr, '"is_custom":true') || InStr(bStr, '"is_custom": true')
                    bCustomName := RegExMatch(bStr, '"custom_name"\s*:\s*"([^"]*)"', &cn) ? cn[1] : pKey

                    defaultMap["providers"][pKey] := Map(
                        "base_url", bUrl,
                        "model", bModel,
                        "api_key", bKey,
                        "is_custom", bIsCustom,
                        "custom_name", bCustomName,
                        "platform_nickname", bCustomName
                    )
                    pos += StrLen(mMatch[0])
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
                .container { padding: 16px 22px; position: relative; height: 100%; box-sizing: border-box; }

                .header-bar { display: table; width: 100%; margin-bottom: 12px; }
                .brand-left { display: table-cell; vertical-align: middle; }
                
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
                    height: 195px;
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
                
                .del-opt-btn {
                    color: #9CA3AF;
                    font-size: 13px;
                    font-weight: bold;
                    padding: 2px 6px;
                    border-radius: 4px;
                    margin-left: 6px;
                    transition: all 0.15s;
                }
                .del-opt-btn:hover {
                    background-color: #EF4444;
                    color: #FFFFFF;
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
                    transition: all 0.25s ease;
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

                .status-spinner {
                    display: inline-block;
                    width: 13px;
                    height: 13px;
                    border: 2px solid rgba(20, 20, 22, 0.2);
                    border-radius: 50%;
                    border-top-color: #141416;
                    animation: spinAnim 0.75s linear infinite;
                    -webkit-animation: spinAnim 0.75s linear infinite;
                    margin-right: 6px;
                    vertical-align: -2px;
                }

                @keyframes spinAnim {
                    0% { transform: rotate(0deg); }
                    100% { transform: rotate(360deg); }
                }

                @-webkit-keyframes spinAnim {
                    0% { -webkit-transform: rotate(0deg); }
                    100% { -webkit-transform: rotate(360deg); }
                }

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
                    transition: all 0.2s ease;
                }
                .btn:disabled {
                    opacity: 0.65;
                    cursor: not-allowed;
                }
                .btn-dark { background: #18181B; color: #FFFFFF; }
                .btn-dark:hover:not(:disabled) { background: #27272A; }
                .btn-lime { background: #D8FA63; color: #18181B; border: 1px solid #C4EC44; }
                .btn-lime:hover:not(:disabled) { background: #C8EA2D; }

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
                                            <div class="select-option" data-value="ko" onclick="selectOption('select-sourceLang', 'ko', '한국语 (Korean)')">한국어 (Korean)</div>
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
                                            <div class="select-option" data-value="ko" onclick="selectOption('select-targetLang', 'ko', '한국어 (韩语)')">한국어 (韩语)</div>
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
                                        <div class="select-scroll-viewport" id="providerViewport" onscroll="updateScroll('select-provider', 'thumb-provider')">
                                            <!-- 由 JS 动态渲染模型列表 -->
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- 动态别名输入框（仅自定义项目显示） -->
                        <div class="form-row" id="rowCustomName" style="display: none;">
                            <div class="form-label">平台昵称</div>
                            <div class="form-field">
                                <input type="text" id="customName" class="input-box" placeholder="如: OneAPI-中转 / 本地Ollama" />
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
                            <button class="btn btn-dark" id="btnTestApi" onclick="triggerCheck()">🚀 检测 API 有效性</button>
                        </div>
                        <div class="btn-cell">
                            <button class="btn btn-lime" id="btnSave" onclick="triggerSave()">💾 保存并生效</button>
                        </div>
                    </div>
                </div>

                <!-- 页面 2: 快捷键设置 -->
                <div class="page-section" id="pageHotkey">
                    <div class="tag">GLOBAL SYSTEM SHORTCUTS</div>
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

                <!-- 底部版本号徽章 -->
                <div style="position: absolute; bottom: 12px; left: 0; right: 0; text-align: center; pointer-events: none;">
                    <span style="display: inline-block; background-color: #D4F658; color: #1A2E05; font-size: 12px; font-weight: bold; padding: 4px 16px; border-radius: 6px; border: 1px solid #c0e840; box-shadow: 0 2px 6px rgba(0,0,0,0.06); pointer-events: auto;">当前版本: {{APP_VERSION}}</span>
                </div>
            </div>

            <script>
                var g_currentProvider = "DeepSeek";
                var g_allConfigs = {
                    "Gemini": { base_url: "https://generativelanguage.googleapis.com/v1beta/openai", model: "gemini-1.5-flash", api_key: "", is_custom: false },
                    "OpenAI": { base_url: "https://api.openai.com/v1", model: "gpt-4o-mini", api_key: "", is_custom: false },
                    "NVIDIA": { base_url: "https://integrate.api.nvidia.com/v1", model: "meta/llama-3.1-8b-instruct", api_key: "", is_custom: false },
                    "Qwen": { base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", api_key: "", is_custom: false },
                    "DeepSeek": { base_url: "https://api.deepseek.com/v1", model: "deepseek-chat", api_key: "", is_custom: false },
                    "Doubao": { base_url: "https://ark.cn-beijing.volces.com/api/v3", model: "ep-xxxxxx", api_key: "", is_custom: false }
                };

                var g_builtinLabels = {
                    "Gemini": "Gemini（需魔法）",
                    "OpenAI": "ChatGPT（需魔法）",
                    "NVIDIA": "NVIDIA·免费满血模型（需魔法）",
                    "Qwen": "通义千问 (阿里百炼·国内直连)",
                    "DeepSeek": "DeepSeek（官方直连·深度思考）",
                    "Doubao": "豆包(ByteDance)"
                };

                var g_hotkeys = {
                    show_bar: "!y",
                    settings: "!s",
                    output_trans: "Enter",
                    output_raw: "^Enter",
                    switch_ai: "Tab"
                };

                var toastTimer = null;

                function renderProviderOptions() {
                    var vp = document.getElementById("providerViewport");
                    if (!vp) return;
                    var html = "";

                    // 1. 系统内置
                    for (var k in g_builtinLabels) {
                        var sel = (k === g_currentProvider) ? " selected" : "";
                        html += '<div class="select-option' + sel + '" data-value="' + k + '" onclick="selectOption(\'select-provider\', \'' + k + '\', \'' + g_builtinLabels[k] + '\')">' + g_builtinLabels[k] + '</div>';
                    }

                    // 2. 自定义模型
                    for (var key in g_allConfigs) {
                        if (!g_builtinLabels[key]) {
                            var item = g_allConfigs[key];
                            var displayName = (item.custom_name || key);
                            var isSel = (key === g_currentProvider) ? " selected" : "";
                            html += '<div class="select-option' + isSel + '" data-value="' + key + '" onclick="selectOption(\'select-provider\', \'' + key + '\', \'' + displayName + '\')">';
                            html += '<span>⚙️ ' + displayName + '</span>';
                            html += '<span class="del-opt-btn" title="删除该自定义模型" onclick="deleteCustomProvider(event, \'' + key + '\')">✕</span>';
                            html += '</div>';
                        }
                    }

                    // 3. 常驻添加新自定义
                    html += '<div class="select-option" style="color:#15803D; font-weight:700; border-top:1px dashed #D9DCD2; margin-top:4px;" data-value="__ADD_NEW__" onclick="addNewCustomProvider()">➕ 添加自定义 API...</div>';
                    vp.innerHTML = html;
                }

                function addNewCustomProvider() {
                    closeAllDropdowns();
                    var newId = "Custom_" + new Date().getTime();
                    g_allConfigs[newId] = {
                        base_url: "https://api.openai.com/v1",
                        model: "gpt-3.5-turbo",
                        api_key: "",
                        is_custom: true,
                        custom_name: "自定义模型 (" + (Object.keys(g_allConfigs).length - 5) + ")"
                    };
                    g_currentProvider = newId;
                    renderProviderOptions();
                    setCustomSelectValue("select-provider", newId);
                    renderCurrentForm();
                    updateStatusText("已创建新自定义配置项，请修改昵称及接口参数后保存。");
                }

                function deleteCustomProvider(e, key) {
                    if (e) e.stopPropagation();
                    if (!confirm("确定要删除自定义模型【" + (g_allConfigs[key].custom_name || key) + "】吗？"))
                        return;

                    delete g_allConfigs[key];
                    if (g_currentProvider === key) {
                        g_currentProvider = "DeepSeek";
                    }
                    renderProviderOptions();
                    setCustomSelectValue("select-provider", g_currentProvider);
                    renderCurrentForm();
                    showCenterToast("已成功删除模型配置", false);
                }

                function switchTab(tabName) {
                    var tabEngine = document.getElementById("tabEngine");
                    var tabHotkey = document.getElementById("tabHotkey");
                    var pageEngine = document.getElementById("pageEngine");
                    var pageHotkey = document.getElementById("pageHotkey");

                    if (tabName === "engine") {
                        tabEngine.className = "pill active";
                        tabHotkey.className = "pill";
                        pageEngine.style.display = "block";
                        pageHotkey.style.display = "none";
                    } else {
                        tabEngine.className = "pill";
                        tabHotkey.className = "pill active";
                        pageEngine.style.display = "none";
                        pageHotkey.style.display = "block";
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

                    var maxThumbTravel = 185 - 36;
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
                    var matched = false;
                    for (var i = 0; i < options.length; i++) {
                        if (options[i].getAttribute("data-value") === value) {
                            el.setAttribute("data-value", value);
                            var sp = options[i].querySelector("span");
                            el.querySelector(".select-text").innerText = sp ? sp.innerText : options[i].innerText;
                            options[i].classList.add("selected");
                            matched = true;
                        } else {
                            options[i].classList.remove("selected");
                        }
                    }
                    if (!matched && g_allConfigs[value]) {
                        el.setAttribute("data-value", value);
                        el.querySelector(".select-text").innerText = g_allConfigs[value].custom_name || value;
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
                    renderProviderOptions();
                    setCustomSelectValue("select-provider", currProvider);
                    setCustomSelectValue("select-sourceLang", sourceLang);
                    setCustomSelectValue("select-targetLang", targetLang);

                    renderCurrentForm();
                    renderHotkeyForm();
                }

                function renderCurrentForm() {
                    var cfg = g_allConfigs[g_currentProvider] || {};
                    var rowName = document.getElementById("rowCustomName");
                    var isCustom = !g_builtinLabels[g_currentProvider];

                    if (isCustom) {
                        rowName.style.display = "table";
                        document.getElementById("customName").value = cfg.custom_name || g_currentProvider;
                    } else {
                        rowName.style.display = "none";
                    }

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
                    saveCurrentFormToMemory();
                    g_currentProvider = newProvider;
                    renderCurrentForm();
                    updateStatusText("已切换至「" + (g_builtinLabels[newProvider] || g_allConfigs[newProvider].custom_name || newProvider) + "」，专属配置已载入。");
                }

                function saveCurrentFormToMemory() {
                    if (!g_allConfigs[g_currentProvider]) {
                        g_allConfigs[g_currentProvider] = {};
                    }
                    var isCustom = !g_builtinLabels[g_currentProvider];
                    g_allConfigs[g_currentProvider].base_url = document.getElementById("baseUrl").value;
                    g_allConfigs[g_currentProvider].model = document.getElementById("modelName").value;
                    g_allConfigs[g_currentProvider].api_key = document.getElementById("apiKey").value;
                    if (isCustom) {
                        var cName = document.getElementById("customName").value.trim() || g_currentProvider;
                        g_allConfigs[g_currentProvider].custom_name = cName;
                        g_allConfigs[g_currentProvider].is_custom = true;
                    }
                }

                function triggerCheck() {
                    var btn = document.getElementById("btnTestApi");
                    if (btn) {
                        btn.disabled = true;
                        btn.innerText = "⏳ 正在检测...";
                    }

                    var card = document.getElementById("statusCard");
                    var txt = document.getElementById("statusText");
                    if (card && txt) {
                        card.style.background = "#D8FA63";
                        card.style.borderColor = "#C4EC44";
                        txt.style.color = "#141416";
                        txt.innerHTML = "<span class=\"status-spinner\"></span> 正在发送连通性探针，测速中...";
                    }

                    var payload = {
                        provider: g_currentProvider,
                        baseUrl: document.getElementById("baseUrl").value,
                        model: document.getElementById("modelName").value,
                        apiKey: document.getElementById("apiKey").value
                    };
                    window.ahk_call("check", JSON.stringify(payload));
                }

                function triggerSave() {
                    saveCurrentFormToMemory();
                    renderProviderOptions();
                    setCustomSelectValue("select-provider", g_currentProvider);

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

                    showCenterToast("全部配置已生效，快捷键与模型列表已同步", false);
                    window.ahk_call("save", JSON.stringify(fullConfigObj));
                }

                function updateCheckStatus(success, msg) {
                    var btn = document.getElementById("btnTestApi");
                    if (btn) {
                        btn.disabled = false;
                        btn.innerText = "🚀 检测 API 有效性";
                    }

                    var card = document.getElementById("statusCard");
                    var txt = document.getElementById("statusText");
                    if (card && txt) {
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
                }

                function updateStatusText(text) {
                    var btn = document.getElementById("btnTestApi");
                    if (btn) {
                        btn.disabled = false;
                        btn.innerText = "🚀 检测 API 有效性";
                    }

                    var card = document.getElementById("statusCard");
                    var txt = document.getElementById("statusText");
                    if (card && txt) {
                        card.style.background = "#D8FA63";
                        card.style.borderColor = "#C4EC44";
                        txt.style.color = "#141416";
                        txt.innerHTML = text;
                        card.scrollTop = 0;
                    }
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