#Requires AutoHotkey v2.0

class FloatBar {
    static gui := 0
    static editCtrl := 0
    static statusCtrl := 0
    static isVisible := false

    ; 显示悬浮翻译框
    static Show() {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.gui.Show()
            WinActivate("ahk_id " . this.gui.Hwnd)
            this.editCtrl.Focus()
            this.isVisible := true
            return
        }

        g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "AI 实时打字翻译")
        g.BackColor := "0x18181B"
        g.MarginX := 12
        g.MarginY := 12
        this.gui := g

        ; 输入框
        g.SetFont("s11 cFFFFFF", "Microsoft YaHei UI")
        this.editCtrl := g.Add("Edit", "w360 r2 -WantReturn -E0x200 Background18181B cFFFFFF", "")
        
        ; 状态提示
        g.SetFont("s9 c84CC16", "Microsoft YaHei UI")
        this.statusCtrl := g.Add("Text", "w360 Center", "Enter 翻译并上屏 · Esc 隐藏")

        ; 按键绑定
        g.OnEvent("Escape", (*) => this.Hide())

        ; 居中偏上定位
        posX := (A_ScreenWidth - 384) // 2
        posY := A_ScreenHeight // 3

        g.Show("x" . posX . " y" . posY . " w384 NoActivate")
        this.gui.Show()
        this.editCtrl.Focus()
        this.isVisible := true
    }

    ; 隐藏悬浮框
    static Hide() {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.gui.Hide()
            this.isVisible := false
        }
    }

    ; 提交翻译
    static Submit() {
        if (!this.editCtrl)
            return
        text := Trim(this.editCtrl.Text)
        if (text == "")
            return

        this.statusCtrl.Text := "⚡ 正在调用 AI 翻译大脑..."
        cfg := SettingsUI.LoadConfig()
        
        SetTimer(() => this._DoTranslate(text, cfg), -10)
    }

    static _DoTranslate(text, cfg) {
        try {
            res := AITranslate.Execute(text, cfg)
            if (res != "") {
                this.Hide()
                this.editCtrl.Text := ""
                this.statusCtrl.Text := "Enter 翻译并上屏 · Esc 隐藏"
                
                ; 自动写入剪贴板并粘贴到当前输入焦点
                A_Clipboard := res
                Sleep(50)
                Send("^v")
            } else {
                this.statusCtrl.Text := "❌ 翻译失败，请检查 API 配置"
            }
        } catch as e {
            this.statusCtrl.Text := "❌ 异常: " . e.Message
        }
    }
}

; 悬浮窗口内按 Enter 触发翻译
#HotIf WinActive("AI 实时打字翻译")
Enter:: {
    FloatBar.Submit()
}
#HotIf