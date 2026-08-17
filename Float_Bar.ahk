#Requires AutoHotkey v2.0
#Include Settings_UI.ahk
#Include AI_Translate.ahk

; ==============================================================================
; 注册鼠标拖拽：按住悬浮窗任意非输入区均可自由移动位置
; ==============================================================================
OnMessage(0x0201, WM_LBUTTONDOWN_DRAG)

WM_LBUTTONDOWN_DRAG(wParam, lParam, msg, hwnd) {
    if (FloatBar.gui && (hwnd == FloatBar.gui.Hwnd || DllCall("GetParent", "ptr", hwnd) == FloatBar.gui.Hwnd)) {
        if (FloatBar.editInput && hwnd != FloatBar.editInput.Hwnd) {
            PostMessage(0xA1, 2, 0, FloatBar.gui.Hwnd) ; WM_NCLBUTTONDOWN = 0xA1, HTCAPTION = 2
        }
    }
}

class FloatBar {
    static gui := 0
    static editInput := 0
    static textResult := 0
    static currentModelTag := 0
    static isTranslating := false
    static debounceTimer := 0
    static hotkeysRegistered := false
    static lastActiveHwnd := 0
    
    static currentProvider := "DeepSeek"

    ; ==========================================================================
    ; 动态获取所有可用模型及 1:1 完整显示名称映射（已修复删除同步问题）
    ; ==========================================================================
    static GetDynamicProviders() {
        cfg := SettingsUI.LoadConfig()
        
        list := []
        titles := Map()

        ; 内置模型标准全称映射
        builtinMap := Map(
            "DeepSeek", "DeepSeek（官方直连·深度思考）",
            "Gemini", "Gemini（需魔法）",
            "OpenAI", "ChatGPT（需魔法）",
            "NVIDIA", "NVIDIA·免费满血模型（需魔法）",
            "Doubao", "豆包(ByteDance)",
            "Qwen", "通义千问 (阿里百炼·国内直连)",
            "Tongyi", "通义千问 (阿里百炼·国内直连)"
        )

        if (cfg.Has("providers") && IsObject(cfg["providers"])) {
            for pKey, pVal in cfg["providers"] {
                if (pKey == "" || InStr(pKey, "添加") || pKey == "添加自定义模型API")
                    continue

                displayName := pKey

                ; 1. 如果是内置模型，赋予标准全称
                if (builtinMap.Has(pKey)) {
                    displayName := builtinMap[pKey]
                } 
                else if (IsObject(pVal)) {
                    ; 2. 如果是自定义模型，精准提取 custom_name 或 platform_nickname
                    if (pVal.Has("custom_name") && pVal["custom_name"] != "") {
                        displayName := pVal["custom_name"]
                    } else if (pVal.Has("platform_nickname") && pVal["platform_nickname"] != "") {
                        displayName := pVal["platform_nickname"]
                    }
                }

                titles[pKey] := displayName
                
                ; 避免重复加入轮换列表
                found := false
                for existingKey in list {
                    if (existingKey == pKey) {
                        found := true
                        break
                    }
                }
                if (!found) {
                    list.Push(pKey)
                }
            }
        }

        ; 保底默认列表
        if (list.Length == 0) {
            list := ["DeepSeek", "Gemini", "OpenAI", "NVIDIA", "Doubao", "Qwen"]
            for k, v in builtinMap {
                titles[k] := v
            }
        }

        return { list: list, titles: titles }
    }

    static GetProviderTitle(key) {
        data := this.GetDynamicProviders()
        if (data.titles.Has(key)) {
            return data.titles[key]
        }
        for k, v in data.titles {
            if (k == key || v == key)
                return v
        }
        return key
    }

    static Create() {
        if (this.gui != 0)
            return

        ; 创建温暖米色置顶悬浮翻译条
        bar := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "AI 实时翻译")
        bar.BackColor := "F4EEDC"
        bar.MarginX := 12
        bar.MarginY := 10
        bar.SetFont("s10.5", "Segoe UI, Microsoft YaHei")

        ; 顶部当前引擎标识
        this.currentModelTag := bar.AddText("x12 y10 w456 h20 c65A30D", "● 当前引擎: " . this.GetProviderTitle(this.currentProvider))
        this.currentModelTag.SetFont("s9.5 bold")

        ; 白底背景框 + 垂直居中输入框
        bar.AddText("x12 y32 w456 h36 BackgroundFFFFFF", "")
        this.editInput := bar.AddEdit("x18 y40 w444 h22 -E0x200 -VScroll -HScroll BackgroundFFFFFF c18181B", "")
        this.editInput.SetFont("s11", "Segoe UI, Microsoft YaHei")
        this.editInput.OnEvent("Change", (ctrl, *) => this.OnInputChange(ctrl.Value))

        ; 翻译结果展示区
        this.textResult := bar.AddText("x12 y78 w456 h46 c3F3F46", "等待输入...")
        this.textResult.SetFont("s11", "Segoe UI, Microsoft YaHei")

        ; 底部快捷键提示
        hint := bar.AddText("x12 y130 w456 h18 c84CC16", "[Enter] 输出翻译  |  [Ctrl+Enter] 输出原文  |  [Tab] 切换模型  |  [Esc] 关闭")
        hint.SetFont("s8.5")

        ; 按 Esc 键隐藏窗口
        bar.OnEvent("Escape", (*) => this.Hide())
        this.gui := bar

        ; 注册悬浮窗口专属快捷键
        if (!this.hotkeysRegistered) {
            HotIf((*) => (this.gui != 0 && WinActive("ahk_id " . this.gui.Hwnd)))
            Hotkey("Enter", (*) => this.ConfirmOutput(true), "On")
            Hotkey("^Enter", (*) => this.ConfirmOutput(false), "On")
            Hotkey("Tab", (*) => this.SwitchNextProvider(), "On")
            HotIf()
            this.hotkeysRegistered := true
        }
    }

    static Toggle() {
        this.Create()
        if (WinActive("ahk_id " . this.gui.Hwnd)) {
            this.Hide()
        } else {
            this.Show()
        }
    }

    ; ==========================================================================
    ; 左下角对齐光标 / 鼠标智能定位算法
    ; ==========================================================================
    static CalculateSmartPosition(barW := 480, barH := 155) {
        targetX := 0
        targetY := 0
        hasCaret := false
        gap := 16 ; 浮窗底部与输入光标之间的垂直安全间隙 (16px)

        ; 1. 读取当前输入焦点光标 (Caret)
        try {
            activeHwnd := WinActive("A")
            if (activeHwnd) {
                threadId := DllCall("GetWindowThreadProcessId", "ptr", activeHwnd, "ptr", 0, "uint")
                guiInfo := Buffer(A_PtrSize == 8 ? 72 : 48, 0)
                NumPut("uint", guiInfo.Size, guiInfo, 0)

                if DllCall("GetGUIThreadInfo", "uint", threadId, "ptr", guiInfo.Ptr) {
                    caretHwnd := NumGet(guiInfo, A_PtrSize == 8 ? 48 : 28, "ptr")
                    left   := NumGet(guiInfo, A_PtrSize == 8 ? 56 : 32, "int")
                    top    := NumGet(guiInfo, A_PtrSize == 8 ? 60 : 36, "int")
                    right  := NumGet(guiInfo, A_PtrSize == 8 ? 64 : 40, "int")
                    bottom := NumGet(guiInfo, A_PtrSize == 8 ? 68 : 44, "int")

                    if (caretHwnd && (right > left || bottom > top)) {
                        pt := Buffer(8, 0)
                        NumPut("int", left, pt, 0)
                        NumPut("int", top, pt, 4)
                        DllCall("ClientToScreen", "ptr", caretHwnd, "ptr", pt.Ptr)
                        
                        screenCaretX := NumGet(pt, 0, "int")
                        screenCaretY := NumGet(pt, 4, "int")

                        if (screenCaretX > 0 && screenCaretY > 0) {
                            targetX := screenCaretX
                            targetY := screenCaretY - barH - gap
                            hasCaret := true
                        }
                    }
                }
            }
        }

        ; 2. 若当前软件未暴露光标，则以鼠标当前位置作为对齐锚点
        if (!hasCaret) {
            CoordMode "Mouse", "Screen"
            MouseGetPos &mX, &mY
            targetX := mX
            targetY := mY - barH - gap
        }

        ; 3. 屏幕边界保护与防溢出
        screenWidth := A_ScreenWidth
        screenHeight := A_ScreenHeight

        if (targetX + barW > screenWidth - 15) {
            targetX := screenWidth - barW - 15
        }
        if (targetX < 15) {
            targetX := 15
        }

        if (targetY < 20) {
            targetY := (hasCaret ? (screenCaretY + 30) : (mY + 25))
        }
        if (targetY + barH > screenHeight - 40) {
            targetY := screenHeight - barH - 40
        }

        return { x: targetX, y: targetY }
    }

    static Show() {
        currActive := WinActive("A")
        if (this.gui == 0 || currActive != this.gui.Hwnd) {
            this.lastActiveHwnd := currActive
        }

        this.Create()
        
        cfg := SettingsUI.LoadConfig()
        if (cfg.Has("current_provider") && cfg["current_provider"] != "") {
            this.currentProvider := cfg["current_provider"]
        }
        
        ; 校验当前 provider 是否在动态可用列表中，若不在则默认切到第一个
        data := this.GetDynamicProviders()
        found := false
        for p in data.list {
            if (p == this.currentProvider) {
                found := true
                break
            }
        }
        if (!found && data.list.Length > 0) {
            this.currentProvider := data.list[1]
        }
        
        this.currentModelTag.Text := "● 当前引擎: " . this.GetProviderTitle(this.currentProvider)
        this.editInput.Value := ""
        this.textResult.Text := "等待输入..."

        pos := this.CalculateSmartPosition(480, 155)
        this.gui.Show("x" . pos.x . " y" . pos.y . " w480 h155")

        this.editInput.Focus()
    }

    static Hide() {
        if (this.gui) {
            this.gui.Hide()
        }
    }

    static OnInputChange(val) {
        val := Trim(val)
        if (val == "") {
            this.textResult.Text := "等待输入..."
            return
        }

        if (this.debounceTimer)
            SetTimer(this.debounceTimer, 0)

        this.debounceTimer := () => this.DoLiveTranslate(val)
        SetTimer(this.debounceTimer, -350)
    }

    static DoLiveTranslate(inputText) {
        if (inputText == "" || this.isTranslating)
            return

        this.isTranslating := true
        this.textResult.Text := "⏳ 正在思考并翻译..."

        cfg := SettingsUI.LoadConfig()
        pConfig := (cfg.Has("providers") && cfg["providers"].Has(this.currentProvider)) ? cfg["providers"][this.currentProvider] : Map()
        targetLang := cfg.Has("target_lang") ? cfg["target_lang"] : "en"
        sourceLang := cfg.Has("source_lang") ? cfg["source_lang"] : "auto"

        res := AITranslator.Request(inputText, pConfig, targetLang, sourceLang)
        this.isTranslating := false

        if (!this.gui || !WinExist("ahk_id " . this.gui.Hwnd))
            return

        if (res.success) {
            this.textResult.Text := res.result
        } else {
            this.textResult.Text := "✕ " . res.msg
        }
    }

    static ConfirmOutput(useTranslation := true) {
        rawText := this.editInput.Value
        transText := this.textResult.Text

        outText := useTranslation ? (InStr(transText, "✕") == 1 ? rawText : transText) : rawText
        if (Trim(outText) != "" && outText != "等待输入..." && outText != "⏳ 正在思考并翻译...") {
            A_Clipboard := outText

            if (this.lastActiveHwnd && WinExist("ahk_id " . this.lastActiveHwnd)) {
                WinActivate("ahk_id " . this.lastActiveHwnd)
                Sleep(60)
                Send("^v")
            } else {
                Send("^v")
            }

            this.editInput.Value := ""
            this.textResult.Text := "等待输入..."
        }
    }

    static SwitchNextProvider() {
        data := this.GetDynamicProviders()
        providerList := data.list
        
        if (providerList.Length == 0)
            return

        currIdx := 1
        for idx, p in providerList {
            if (StrCompare(p, this.currentProvider, false) == 0) {
                currIdx := idx
                break
            }
        }
        
        nextIdx := (currIdx >= providerList.Length) ? 1 : currIdx + 1
        this.currentProvider := providerList[nextIdx]
        
        this.currentModelTag.Text := "● 当前引擎: " . this.GetProviderTitle(this.currentProvider)

        (Trim(this.editInput.Value) != "") ? this.DoLiveTranslate(this.editInput.Value) : ""
    }
}