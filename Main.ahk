#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent(true)

#Include Settings_UI.ahk
#Include Float_Bar.ahk

class AppController {
    static boundHotkeys := Map()

    static Init() {
        ; 注册设置变更时的热键动态刷新回调
        SettingsUI.onHotkeysUpdatedCallback := () => this.ReloadHotkeys()
        this.ReloadHotkeys()
        
        ; 初始化托盘菜单
        this.InitTrayMenu()
    }

    static ReloadHotkeys() {
        ; 1. 先注销此前已绑定的所有热键
        for hkKey, hkFunc in this.boundHotkeys {
            try Hotkey(hkKey, "Off")
        }
        this.boundHotkeys.Clear()

        ; 2. 获取当前最新的配置
        cfg := SettingsUI.LoadConfig()
        hkMap := cfg.Has("hotkeys") ? cfg["hotkeys"] : Map()

        showBarHk := hkMap.Has("show_bar") ? this.NormalizeHotkey(hkMap["show_bar"]) : "!y"
        settingsHk := hkMap.Has("settings") ? this.NormalizeHotkey(hkMap["settings"]) : "!s"

        ; 3. 重新绑定全局唤出热键
        try {
            Hotkey(showBarHk, (*) => FloatBar.Toggle(), "On")
            this.boundHotkeys[showBarHk] := true
        } catch as err {
            MsgBox("注册唤出翻译快捷键 [" . showBarHk . "] 失败: " . err.Message, "热键冲突", 16)
        }

        try {
            Hotkey(settingsHk, (*) => SettingsUI.Show(), "On")
            this.boundHotkeys[settingsHk] := true
        } catch as err {
            MsgBox("注册打开设置快捷键 [" . settingsHk . "] 失败: " . err.Message, "热键冲突", 16)
        }
    }

    ; 标准化热键：将字母转换为小写，防止 !Y 变成 Alt+Shift+Y
    static NormalizeHotkey(hkStr) {
        hkStr := Trim(hkStr)
        if (hkStr == "")
            return ""
        
        prefix := ""
        mainKey := ""
        while RegExMatch(hkStr, "^([!^#+])(.*)$", &m) {
            prefix .= m[1]
            hkStr := m[2]
        }
        mainKey := StrLower(hkStr)
        return prefix . mainKey
    }

    static InitTrayMenu() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("打开翻译浮条 (Alt+Y)", (*) => FloatBar.Toggle())
        A_TrayMenu.Add("设置中心 (Alt+S)", (*) => SettingsUI.Show())
        A_TrayMenu.Add()
        A_TrayMenu.Add("重启程序", (*) => Reload())
        A_TrayMenu.Add("退出程序", (*) => ExitApp())
        A_IconTip := "AI 智能打字翻译 (已就绪)"
        A_TrayMenu.Default := "设置中心 (Alt+S)"
    }
}

; 核心启动入口：执行初始化并常驻运行
AppController.Init()