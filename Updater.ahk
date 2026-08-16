#Requires AutoHotkey v2.0

class AppUpdater {
    ; GitHub 仓库地址配置
    static rawBaseUrl := "https://ghproxy.net/https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static directRawUrl := "https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static versionFile := A_ScriptDir . "\version.txt"
    static gui := 0
    static isUpdating := false

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

    ; 发起 HTTP 请求 (带防缓存机制)
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

    ; 检查更新入口
    static Check(isSilent := false) {
        SetTimer(() => this._DoCheck(isSilent), -200)
    }

    static _DoCheck(isSilent) {
        localVer := this.GetLocalVersion()
        
        ; 优先通过加速代理请求，失败则直连
        jsonStr := this.FetchText(this.rawBaseUrl . "/version.json")
        if (jsonStr == "") {
            jsonStr := this.FetchText(this.directRawUrl . "/version.json")
        }

        if (jsonStr == "") {
            if (!isSilent)
                MsgBox("无法连接到更新服务器，请检查网络连接。", "检查更新失败", "Iconx")
            return
        }

        ; 解析 version.json
        remoteVer := RegExMatch(jsonStr, '"version"\s*:\s*"([^"]+)"', &mVer) ? mVer[1] : ""
        changelog := RegExMatch(jsonStr, 's)"changelog"\s*:\s*"([^"]*)"', &mLog) ? mLog[1] : "性能优化与问题修复。"
        
        ; 解析待更新文件列表
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

        ; 反转义换行符
        changelog := StrReplace(changelog, "\n", "`r`n")
        changelog := StrReplace(changelog, '\"', '"')

        ; 比对版本
        if (remoteVer != "" && this.CompareVersions(remoteVer, localVer) > 0) {
            this.ShowUpdateDialog(remoteVer, localVer, changelog, fileList)
        } else if (!isSilent) {
            MsgBox("当前已是最新版本 (v" . localVer . ")，无需更新。", "检查更新", "Iconi")
        }
    }

    ; 展示更新弹窗 (+AlwaysOnTop 强制置顶于主界面之上)
    static ShowUpdateDialog(remoteVer, localVer, changelog, fileList) {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            WinActivate("ahk_id " . this.gui.Hwnd)
            return
        }

        ; 核心修复：添加 +AlwaysOnTop 和 +OwnDialogs 确保窗口始终位于顶层最前端
        g := Gui("+AlwaysOnTop +OwnDialogs -MaximizeBox -MinimizeBox", "发现新版本")
        g.BackColor := "0xFFFFFF"
        g.MarginX := 24
        g.MarginY := 20
        this.gui := g

        ; 标题区域
        g.SetFont("s15 bold c0x0F80E6", "Microsoft YaHei UI")
        g.Add("Text", "w380", "🚀 发现新版本")

        g.SetFont("s10 bold c0x22C55E", "Microsoft YaHei UI")
        txtVer := g.Add("Text", "w380 y+4", "v" . remoteVer . "  ")
        g.SetFont("s9 norm c0x64748B", "Microsoft YaHei UI")
        txtSub := g.Add("Text", "x+0 yp", "(当前版本: v" . localVer . ")")

        ; 更新日志区域
        g.SetFont("s10 bold c0x1E293B", "Microsoft YaHei UI")
        g.Add("Text", "x24 y+18 w380", "📜 更新内容")

        g.SetFont("s9 norm c0x334155", "Microsoft YaHei UI")
        edtLog := g.Add("Edit", "x24 y+8 w380 r5 ReadOnly -E0x200 +Border Background0xFAFAFA", changelog)

        ; 底部提示
        g.SetFont("s8 norm c0x94A3B8", "Microsoft YaHei UI")
        g.Add("Text", "x24 y+14 w380 Center", "为保障系统稳定性，建议立即更新体验")

        ; 更新按钮
        g.SetFont("s10 bold c0x052e16", "Microsoft YaHei UI")
        btnUpdate := g.Add("Button", "x24 y+10 w380 h42 Default Background0x86EFAC", "🚀 立即下载并更新")
        
        ; 状态文本
        txtStatus := g.Add("Text", "x24 y+8 w380 Center Hidden c0x0F80E6", "正在高速下载更新组件...")

        btnUpdate.OnEvent("Click", (*) => this.PerformUpdate(btnUpdate, txtStatus, remoteVer, fileList))
        g.OnEvent("Close", (*) => g.Destroy())

        ; 居中显示并强行置顶激活
        g.Show("w428 Center")
        WinSetAlwaysOnTop(1, "ahk_id " . g.Hwnd)
        WinActivate("ahk_id " . g.Hwnd)
    }

    ; 执行组件下载覆盖
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
            txtStatus.Text := "正在下载组件 (" . idx . "/" . fileList.Length . "): " . fileName
            
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
            txtStatus.Text := "✅ 更新完成！正在为您重新加载程序..."
            Sleep(1000)

            ; 自动重启程序
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
            txtStatus.Text := "❌ 部分文件下载失败，请检查网络后重试"
        }
    }
}