#Requires AutoHotkey v2.0

OnMessage(0x0084, WM_NCHITTEST)

WM_NCHITTEST(wParam, lParam, msg, hwnd) {
    if (FloatBar.gui && hwnd == FloatBar.gui.Hwnd) {
        x := lParam & 0xFFFF
        y := (lParam >> 16) & 0xFFFF
        DllCall("ScreenToClient", "ptr", hwnd, "ptr", buf := Buffer(8, 0))
        NumPut("int", x, buf, 0)
        NumPut("int", y, buf, 4)
        
        cX := NumGet(buf, 0, "int")
        cY := NumGet(buf, 4, "int")

        if (FloatBar.editInput) {
            FloatBar.editInput.GetPos(&eX, &eY, &eW, &eH)
            if (cX >= eX && cX <= eX + eW && cY >= eY && cY <= eY + eH)
                return 1
        }

        return 2
    }
}

class FloatBar {
    static gui := 0
    static editInput := 0
    static textResult := 0
    static currentModelTag := 0
    static currentModelIcon := 0
    static customEmojiTag := 0
    static currentModelLabel := 0
    
    ; 绝对路径指向本地图标文件夹，实现极致秒开
    static iconDir := "F:\AI-Live-Translator\assets\icons"
    
    static isTranslating := false
    static hotkeysRegistered := false
    static lastActiveHwnd := 0
    
    static currentProvider := "DeepSeek"

    static GetDynamicProviders() {
        cfg := SettingsUI.LoadConfig()
        list := []
        titles := Map()

        builtinMap := Map(
            "DeepSeek", "DeepSeek（官方直连·深度思考）",
            "Gemini", "Gemini（需魔法）",
            "OpenAI", "ChatGPT（需魔法）",
            "NVIDIA", "NVIDIA·免费满血模型（需魔法）",
            "Meta",     "Meta（需魔法）",
            "Doubao", "豆包(ByteDance)",
            "Qwen",   "通义千问 (阿里百炼·国内直连)"
        )

        if (cfg.Has("providers") && IsObject(cfg["providers"])) {
            for pKey, pVal in cfg["providers"] {
                if (pKey == "" || InStr(pKey, "添加") || pKey == "添加自定义模型API")
                    continue
                
                displayName := pKey
                if (builtinMap.Has(pKey)) {
                    displayName := builtinMap[pKey]
                } else if (IsObject(pVal)) {
                    if (pVal.Has("custom_name") && pVal["custom_name"] != "")
                        displayName := pVal["custom_name"]
                }
                titles[pKey] := displayName
                list.Push(pKey)
            }
        }
        if (list.Length == 0) {
            list := ["DeepSeek", "Gemini", "OpenAI", "NVIDIA", "Meta", "Doubao", "Qwen"]
            for k, v in builtinMap
                titles[k] := v
        }
        return { list: list, titles: titles }
    }

    static GetProviderTitle(key) {
        data := this.GetDynamicProviders()
        return data.titles.Has(key) ? data.titles[key] : key
    }

    static GetProviderIconFile(key) {
        iconMap := Map(
            "Gemini",  "Gemini.png",
            "OpenAI",  "GPT.png",
            "NVIDIA",  "nvidia.png",
            "Meta",    "meta.png",
            "Qwen",    "qwen.png",
            "DeepSeek","deepseek.png",
            "Doubao",  "doubao.png"
        )
        fileName := iconMap.Has(key) ? iconMap[key] : (StrLower(key) . ".png")
        filePath := this.iconDir "\" fileName
        return FileExist(filePath) ? filePath : ""
    }

    static IsBuiltinProvider(key) {
        return Map("Gemini",1, "OpenAI",1, "NVIDIA",1, "Meta",1, "Qwen",1, "DeepSeek",1, "Doubao",1).Has(key)
    }

    static UpdateCurrentProviderDisplay() {
        if (!this.currentModelTag || !this.currentModelIcon || !this.customEmojiTag)
            return

        title := this.GetProviderTitle(this.currentProvider)
        this.currentModelTag.Text := title

        if (this.IsBuiltinProvider(this.currentProvider)) {
            this.customEmojiTag.Visible := false
            iconFile := this.GetProviderIconFile(this.currentProvider)
            if (iconFile != "") {
                try {
                    this.currentModelIcon.Value := iconFile
                    this.currentModelIcon.Visible := true
                    this.currentModelIcon.Move(, 8)
                } catch {
                    this.currentModelIcon.Visible := false
                }
            } else {
                this.currentModelIcon.Visible := false
            }
        } else {
            this.currentModelIcon.Visible := false
            this.customEmojiTag.Visible := true
            this.customEmojiTag.Move(, 6)
        }
    }

    static Create() {
        if (this.gui != 0)
            return

        bar := Gui("+AlwaysOnTop -Caption +ToolWindow", "AI 实时翻译")
        bar.BackColor := "F4EEDC"
        bar.MarginX := 12
        bar.MarginY := 10
        bar.SetFont("s10.5", "Segoe UI, Microsoft YaHei")

        this.currentModelLabel := bar.AddText("x12 y9 w96 h20 c65A30D", "● 当前引擎:")
        this.currentModelLabel.SetFont("s9.5 bold")

        initialIcon := this.GetProviderIconFile(this.currentProvider)
        if (initialIcon != "") {
            this.currentModelIcon := bar.AddPicture("x110 y8 w16 h16", initialIcon)
        } else {
            this.currentModelIcon := bar.AddPicture("x110 y8 w16 h16 Hidden", A_AhkPath)
        }

        this.customEmojiTag := bar.AddText("x110 y6 w20 h20 Hidden", "🤖")
        this.customEmojiTag.SetFont("s9.5", "Segoe UI Emoji")

        this.currentModelTag := bar.AddText("x130 y9 w394 h20 c65A30D", "")
        this.currentModelTag.SetFont("s9.5 bold")
        this.UpdateCurrentProviderDisplay()

        bar.AddText("x14 y33 w512 h34 BackgroundF3F4EE 0x1", "")
        bar.AddText("x16 y32 w508 h1 Background84CC16 0x1", "")
        bar.AddText("x16 y67 w508 h1 Background84CC16 0x1", "")
        bar.AddText("x15 y33 w1 h35 Background84CC16 0x1", "")
        bar.AddText("x524 y33 w1 h35 Background84CC16 0x1", "")

        this.editInput := bar.AddEdit("x18 y37 w504 h26 -E0x200 -VScroll -HScroll BackgroundF3F4EE c18181B", "")
        this.editInput.SetFont("s11", "Segoe UI, Microsoft YaHei")
        this.editInput.OnEvent("Change", (ctrl, *) => this.OnInputChange(ctrl.Value))

        this.textResult := bar.AddText("x12 y78 w516 h46 c3F3F46", "等待输入...")
        this.textResult.SetFont("s11", "Segoe UI, Microsoft YaHei")

        hint := bar.AddText("x12 y130 w516 h18 c84CC16", "[Enter]输出 | [Ctrl+Enter]原文 | 粘贴[Ctrl+Alt+Y] | [Tab]切换 | [Esc]关闭")
        hint.SetFont("s8.5 bold")

        bar.OnEvent("Escape", (*) => this.Hide())
        this.gui := bar

        if (!this.hotkeysRegistered) {
            HotIf((*) => (this.gui != 0 && WinActive("ahk_id " . this.gui.Hwnd)))
            Hotkey("Enter", (*) => this.ConfirmOutput(true), "On")
            Hotkey("^Enter", (*) => this.ConfirmOutput(false), "On")
            Hotkey("Tab", (*) => this.SwitchNextProvider(), "On")
            HotIf()

            Hotkey("^!y", (*) => this.PasteAndTranslate(), "On")
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

    static PasteAndTranslate() {
        currActive := WinActive("A")
        if (this.gui == 0 || currActive != this.gui.Hwnd) {
            this.lastActiveHwnd := currActive
        }

        A_Clipboard := ""
        Send("^c")
        ClipWait(0.4)
        
        clipContent := A_Clipboard

        this.Create()
        pos := this.CalculateSmartPosition(540, 155)
        this.gui.Show("x" . pos.x . " y" . pos.y . " w540 h155")

        cfg := SettingsUI.LoadConfig()
        if (cfg.Has("current_provider") && cfg["current_provider"] != "") {
            this.currentProvider := cfg["current_provider"]
        }
        this.UpdateCurrentProviderDisplay()

        if (Trim(clipContent) != "") {
            this.editInput.Value := clipContent
            ; 💡 修复：主动调用 OnInputChange 启动 400ms 防抖并触发翻译
            this.OnInputChange(clipContent)
        } else {
            this.editInput.Value := ""
            this.textResult.Text := "等待输入..."
        }
        this.editInput.Focus()
    }

    static CalculateSmartPosition(barW := 540, barH := 155) {
        targetX := 0
        targetY := 0
        hasCaret := false
        gap := 16

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

        if (!hasCaret) {
            CoordMode "Mouse", "Screen"
            MouseGetPos &mX, &mY
            targetX := mX
            targetY := mY - barH - gap
        }

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
        
        this.UpdateCurrentProviderDisplay()
        this.editInput.Value := ""
        this.textResult.Text := "等待输入..."

        pos := this.CalculateSmartPosition(540, 155)
        this.gui.Show("x" . pos.x . " y" . pos.y . " w540 h155")

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

        ; 400ms 统一防抖缓冲定时器
        SetTimer(() => this.DoLiveTranslate(val), -400)
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
        
        this.UpdateCurrentProviderDisplay()

        (Trim(this.editInput.Value) != "") ? this.DoLiveTranslate(this.editInput.Value) : ""
    }
}