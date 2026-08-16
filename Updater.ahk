#Requires AutoHotkey v2.0

class AppUpdater {
    ; GitHub 仓库地址配置
    static rawBaseUrl := "https://ghproxy.net/https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static directRawUrl := "https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static versionFile := A_ScriptDir . "\version.txt"
    static gui := 0
    static isUpdating := false
    static isRequired := true ; 强制更新模式

    ; 获取本地版本号
    static GetLocalVersion() {
        if FileExist(this.versionFile) {
            try {
                v := Trim(FileRead(this.versionFile, "UTF-8"))
                if (v != "")
                    return v
            }
        }
        return "1.0.0"
    }

    ; 版本号比对算法 (v1 > v2 返回 1, v1 < v2 返回 -1, 相等返回 0)
    static CompareVersions(v1, v2) {
        v1 := RegExReplace(v1, "^[vV]", "")
        v2 := RegExReplace(v2, "^[vV]", "")
        
        parts1 := StrSplit(v1, ".")
        parts2 := StrSplit(v2, ".")
        
        maxLen := Max(parts1.Length, parts2.Length)
        Loop maxLen {
            p1 := (A_Index <= parts1.Length && parts1[A_Index] != "") ? Integer(parts1[A_Index]) : 0
            p2 := (A_Index <= parts2.Length && parts2[A_Index] != "") ? Integer(parts2[A_Index]) : 0
            if (p1 > p2)
                return 1
            if (p1 < p2)
                return -1
        }
        return 0
    }

    ; 防缓存 HTTP 请求
    static FetchText(url) {
        reqUrl := url . (InStr(url, "?") ? "&" : "?") . "_t=" . A_TickCount
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.SetTimeouts(5000, 5000, 10000, 10000)
            http.Open("GET", reqUrl, false)
            http.SetRequestHeader("Pragma", "no-cache")
            http.SetRequestHeader("Cache-Control", "no-cache, no-store, must-revalidate")
            http.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            http.Send()
            if (http.Status == 200)
                return http.ResponseText
        } catch {
        }
        return ""
    }

    ; 供主界面拦截调用的窗口抖动提醒方法 (修复报错 Bug 2)
    static ShakeModal() {
        if (!this.gui || !WinExist("ahk_id " . this.gui.Hwnd))
            return
        
        try {
            WinActivate("ahk_id " . this.gui.Hwnd)
            this.gui.GetPos(&gx, &gy, &gw, &gh)
            Loop 2 {
                this.gui.Move(gx - 8, gy)
                Sleep 25
                this.gui.Move(gx + 8, gy)
                Sleep 25
            }
            this.gui.Move(gx, gy)
        }
    }

    ; 检查更新入口
    static Check(isSilent := false) {
        SetTimer(() => this._DoCheck(isSilent), -150)
    }

    static _DoCheck(isSilent) {
        localVer := this.GetLocalVersion()
        
        jsonStr := this.FetchText(this.rawBaseUrl . "/version.json")
        if (jsonStr == "") {
            jsonStr := this.FetchText(this.directRawUrl . "/version.json")
        }

        if (jsonStr == "") {
            if (!isSilent)
                MsgBox("无法连接到更新服务器，请检查网络。", "检查更新失败", "Iconx")
            return
        }

        remoteVer := RegExMatch(jsonStr, '"version"\s*:\s*"([^"]+)"', &mVer) ? mVer[1] : ""
        changelog := RegExMatch(jsonStr, 's)"changelog"\s*:\s*"([^"]*)"', &mLog) ? mLog[1] : "系统性能优化与稳定性提升。"
        
        fileList := []
        if RegExMatch(jsonStr, 's)"files"\s*:\s*\[(.*?)\]', &mFiles) {
            filesBlock := mFiles[1]
            pos := 1
            while RegExMatch(filesBlock, '"([^"]+)"', &fMatch, pos) {
                fileList.Push(fMatch[1])
                pos := fMatch.Pos + StrLen(fMatch[0])
            }
        }

        if (fileList.Length == 0) {
            fileList := ["AI_Translate.ahk", "Float_Bar.ahk", "Main.ahk", "Settings_UI.ahk", "Updater.ahk"]
        }

        changelog := StrReplace(changelog, "\n", "`r`n")
        changelog := StrReplace(changelog, '\"', '"')

        if (remoteVer != "" && this.CompareVersions(remoteVer, localVer) > 0) {
            this.ShowUpdateDialog(remoteVer, localVer, changelog, fileList)
        } else if (!isSilent) {
            MsgBox("当前已是最新版本 (v" . localVer . ")，无需更新。", "检查更新", "Iconi")
        }
    }

    ; 现代 UI 弹窗设计 (无关闭按钮 + 强模态锁定 + 统一配色)
    static ShowUpdateDialog(remoteVer, localVer, changelog, fileList) {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.ShakeModal()
            return
        }

        ; -SysMenu 去除右上角 X 关闭按钮，+AlwaysOnTop 强制最前
        g := Gui("+AlwaysOnTop +OwnDialogs -MaximizeBox -MinimizeBox -SysMenu", "系统更新")
        g.BackColor := "0xF8FAF5"
        g.MarginX := 24
        g.MarginY := 20
        this.gui := g

        ; 头部：Logo / 胶囊徽章
        g.SetFont("s10 bold c0x18181B", "Microsoft YaHei UI")
        g.Add("Text", "w360", "⚡ LIVE INTELLIGENT UPDATER")

        g.SetFont("s15 bold c0x0F172A", "Microsoft YaHei UI")
        g.Add("Text", "w360 y+4", "发现新版本可用")

        ; 版本对比横向信息栏 (避免换行截断)
        g.SetFont("s10 bold c0x15803D", "Microsoft YaHei UI")
        vText := "v" . remoteVer . "  "
        g.Add("Text", "y+6", vText)
        g.SetFont("s9 norm c0x64748B", "Microsoft YaHei UI")
        g.Add("Text", "x+0 yp", "(当前版本: v" . localVer . ")")

        ; 更新内容说明框
        g.SetFont("s9 bold c0x334155", "Microsoft YaHei UI")
        g.Add("Text", "x24 y+14 w360", "📦 更新日志与功能变更：")

        g.SetFont("s9 norm c0x1E293B", "Microsoft YaHei UI")
        edtLog := g.Add("Edit", "x24 y+6 w360 r5 ReadOnly -E0x200 +Border Background0xFFFFFF", changelog)

        ; 底部强制更新提醒
        g.SetFont("s8 norm c0x94A3B8", "Microsoft YaHei UI")
        g.Add("Text", "x24 y+12 w360 Center", "⚠️ 此版本包含重要功能重构，必须完成更新后方可使用")

        ; 主按钮 (黑底配合荧光绿文字，与主界面 [检测 API 有效性] 风格一致)
        g.SetFont("s10 bold c0xD8FA63", "Microsoft YaHei UI")
        btnUpdate := g.Add("Button", "x24 y+10 w360 h44 Default Background0x18181B", "🚀 立即下载并应用更新")
        
        ; 状态文本
        txtStatus := g.Add("Text", "x24 y+8 w360 Center Hidden c0x0F80E6", "正在下载核心组件...")

        btnUpdate.OnEvent("Click", (*) => this.PerformUpdate(btnUpdate, txtStatus, remoteVer, fileList))

        ; 显示并居中置顶
        g.Show("w408 Center")
        WinSetAlwaysOnTop(1, "ahk_id " . g.Hwnd)
        WinActivate("ahk_id " . g.Hwnd)
    }

    ; 执行更新与组件覆写
    static PerformUpdate(btn, txtStatus, remoteVer, fileList) {
        if (this.isUpdating)
            return
        this.isUpdating := true

        btn.Visible := false
        txtStatus.Visible := true
        txtStatus.Text := "正在下载核心组件 (0/" . fileList.Length . ")..."

        successCount := 0
        tempDir := A_ScriptDir . "\~temp_update"
        if !DirExist(tempDir)
            DirCreate(tempDir)

        for idx, fileName in fileList {
            txtStatus.Text := "正在同步组件 (" . idx . "/" . fileList.Length . "): " . fileName
            
            fileUrl := this.rawBaseUrl . "/" . fileName
            fileContent := this.FetchText(fileUrl)
            
            if (fileContent == "") {
                fileUrl := this.directRawUrl . "/" . fileName
                fileContent := this.FetchText(fileUrl)
            }

            if (fileContent != "") {
                tempPath := tempDir . "\" . fileName
                try {
                    if FileExist(tempPath)
                        FileDelete(tempPath)
                    FileAppend(fileContent, tempPath, "UTF-8")
                    successCount++
                }
            }
        }

        if (successCount >= fileList.Length) {
            ; 替换实际文件
            for fileName in fileList {
                src := tempDir . "\" . fileName
                dst := A_ScriptDir . "\" . fileName
                if FileExist(src) {
                    try {
                        if FileExist(dst)
                            FileDelete(dst)
                        FileMove(src, dst, 1)
                    }
                }
            }

            ; 写入新版本号
            try {
                if FileExist(this.versionFile)
                    FileDelete(this.versionFile)
                FileAppend(remoteVer, this.versionFile, "UTF-8")
            }

            try DirDelete(tempDir, 1)

            txtStatus.SetFont("c0x16A34A")
            txtStatus.Text := "✅ 更新成功！正在重新启动程序..."
            Sleep(800)

            ; 自动重新加载程序
            if A_IsCompiled {
                Run('"' . A_ScriptFullPath . '"')
            } else {
                Run('"' . A_AhkPath . '" "' . (FileExist(A_ScriptDir . "\Main.ahk") ? A_ScriptDir . "\Main.ahk" : A_ScriptFullPath) . '"')
            }
            ExitApp()
        } else {
            this.isUpdating := false
            btn.Visible := true
            txtStatus.SetFont("c0xDC2626")
            txtStatus.Text := "❌ 部分组件下载失败，请检查网络后重试"
        }
    }
}