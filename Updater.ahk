#Requires AutoHotkey v2.0

; ==============================================================================
; 注册底层窗口消息拦截：禁止移动/拖拽更新窗口，强制固定居中
; ==============================================================================
OnMessage(0x00A1, WM_NCLBUTTONDOWN_LOCK, 2)
OnMessage(0x0112, WM_SYSCOMMAND_LOCK, 2)

WM_NCLBUTTONDOWN_LOCK(wParam, lParam, msg, hwnd) {
    if (AppUpdater.gui && hwnd == AppUpdater.gui.Hwnd && wParam == 2)
        return 0
}

WM_SYSCOMMAND_LOCK(wParam, lParam, msg, hwnd) {
    if (AppUpdater.gui && hwnd == AppUpdater.gui.Hwnd && (wParam & 0xFFF0) == 0xF010)
        return 0
}

class AppUpdater {
    static defaultVersion := "1.0.0"
    static versionFile    := A_ScriptDir . "\version.txt"
    static gui            := 0
    static isShaking      := false
    
    ; GitHub 仓库配置
    static githubUser := "hyd169888-creator"
    static githubRepo := "dasdada"
    static branch     := "main"
    
    static rawUrlBase := "https://ghproxy.net/https://raw.githubusercontent.com/"

    static GetCurrentVersion() {
        if FileExist(this.versionFile) {
            try {
                ver := Trim(FileRead(this.versionFile, "UTF-8"))
                if (ver != "")
                    return ver
            }
        }
        return this.defaultVersion
    }

    static SaveCurrentVersion(newVer) {
        try {
            f := FileOpen(this.versionFile, "w", "UTF-8")
            f.Write(Trim(newVer))
            f.Close()
        }
    }

    static Check(silent := false) {
        url := this.rawUrlBase . this.githubUser . "/" . this.githubRepo . "/" . this.branch . "/version.json"
        curVer := this.GetCurrentVersion()
        
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", url, true)
            http.SetTimeouts(2000, 2000, 3000, 3000)
            http.Send()
            http.WaitForResponse(3)
            
            if (http.Status != 200) {
                if (!silent)
                    this.ShowAlert("无法连接至更新服务器 (HTTP " . http.Status . ")", "更新提示", "warning")
                return
            }

            respText := http.ResponseText
            remoteInfo := this.ParseJson(respText)
            
            if (!remoteInfo.Has("version")) {
                if (!silent)
                    this.ShowAlert("远程版本信息解析异常。", "更新提示", "warning")
                return
            }

            latestVer := remoteInfo["version"]
            changelog := remoteInfo.Has("changelog") ? remoteInfo["changelog"] : "常规性能优化与体验提升。"
            filesToUpdate := remoteInfo.Has("files") ? remoteInfo["files"] : []

            if (this.CompareVersion(latestVer, curVer) > 0) {
                this.ShowUpdateModal(latestVer, curVer, changelog, filesToUpdate)
            } else {
                if (!silent)
                    this.ShowAlert("当前已是最新版本 (v" . curVer . ")，无需更新！", "检查更新", "success")
            }
        } catch as err {
            if (!silent)
                this.ShowAlert("检查更新网络异常: " . err.Message, "更新异常", "error")
        }
    }

    ; =========================================================================
    ; 窗口快速抖动警示动画
    ; =========================================================================
    static ShakeModal() {
        if (!this.gui || this.isShaking)
            return
        
        this.isShaking := true
        this.gui.GetPos(&gx, &gy, &gw, &gh)
        
        offsets := [-10, 10, -8, 8, -5, 5, 0]
        for dx in offsets {
            try this.gui.Move(gx + dx, gy)
            Sleep(25)
        }
        this.isShaking := false
    }

    ; 自定义更新弹窗 (非全局置顶，正常随主程序层级流动，模态绑定主窗口)
    static ShowUpdateModal(latestVer, currentVer, changelog, files) {
        if (this.gui != 0) {
            this.ShakeModal()
            return
        }

        ownerHwnd := 0
        if (WinExist("AI 智能打字翻译 - 设置中心"))
            ownerHwnd := WinGetID("AI 智能打字翻译 - 设置中心")

        ; 移除 +AlwaysOnTop，使用 -AlwaysOnTop，允许被外部其它程序遮挡
        opt := "-AlwaysOnTop -SysMenu -MinimizeBox -MaximizeBox"
        if (ownerHwnd)
            opt .= " +Owner" . ownerHwnd

        uGui := Gui(opt, "发现新版本")
        uGui.MarginX := 0
        uGui.MarginY := 0
        uGui.BackColor := "FFFFFF"
        
        wbCtrl := uGui.AddActiveX("x0 y0 w410 h320", "Shell.Explorer")
        wbCtrl.Value.Silent := true
        wbCtrl.Value.Navigate("about:blank")
        while wbCtrl.Value.ReadyState != 4
            Sleep(10)

        html := this.GetModalHTML()
        html := StrReplace(html, "{{LATEST_VER}}", latestVer)
        html := StrReplace(html, "{{CURRENT_VER}}", currentVer)

        htmlLog := StrReplace(changelog, "`n", "<br>")
        htmlLog := StrReplace(htmlLog, "\n", "<br>")
        html := StrReplace(html, "{{CHANGELOG}}", htmlLog)

        doc := wbCtrl.Value.Document
        doc.open()
        doc.write(html)
        doc.close()

        doc.parentWindow.ahk_download := () => this.StartDownload(uGui, doc, files, latestVer)

        this.gui := uGui
        uGui.OnEvent("Close", (*) => ExitApp())
        uGui.Show("w410 h320 Center")

        ; 模态禁用主窗口（防止拖动或点击主窗口）
        if (ownerHwnd) {
            try WinSetEnabled(0, "ahk_id " . ownerHwnd)
        }
    }

    ; 执行热下载与动态版本保存
    static StartDownload(uGui, doc, files, newVer) {
        if (files.Length == 0) {
            try doc.parentWindow.setFailed("⚠️ 更新列表中没有待下载的文件")
            return
        }

        successCount := 0
        for index, fileName in files {
            try doc.parentWindow.setProgress("正在下载 (" . index . "/" . files.Length . "): " . fileName)
            fileUrl := this.rawUrlBase . this.githubUser . "/" . this.githubRepo . "/" . this.branch . "/" . fileName
            localPath := A_ScriptDir . "\" . fileName

            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.Open("GET", fileUrl, false)
                http.Send()

                if (http.Status == 200) {
                    fileObj := FileOpen(localPath, "w", "UTF-8")
                    fileObj.Write(http.ResponseText)
                    fileObj.Close()
                    successCount++
                }
            } catch {
                continue
            }
        }

        if (successCount > 0) {
            this.SaveCurrentVersion(newVer)
            try doc.parentWindow.setProgress("✅ 升级至 v" . newVer . " 成功！正在重启...")
            Sleep(800)
            
            if (WinExist("AI 智能打字翻译 - 设置中心"))
                try WinSetEnabled(1, WinGetID("AI 智能打字翻译 - 设置中心"))

            uGui.Destroy()
            this.gui := 0
            Reload()
        } else {
            try doc.parentWindow.setFailed("❌ 下载失败，请检查网络后重试")
        }
    }

    static ShowAlert(msg, title := "提示", type := "info") {
        aGui := Gui("-MinimizeBox -MaximizeBox", title)
        aGui.BackColor := "FFFFFF"
        aGui.SetFont("s10", "Microsoft YaHei UI")
        
        iconText := (type == "success") ? "✅ " : ((type == "warning") ? "⚠️ " : ((type == "error") ? "❌ " : "ℹ️ "))
        aGui.SetFont("s10 Bold", "Microsoft YaHei UI")
        aGui.AddText("x24 y20 w280 Center c1E293B", iconText . msg)
        
        btnOk := aGui.AddText("x114 y58 w100 h30 Center 0x200 BackgroundD4F658 c1A2E05 +Border", "确定")
        btnOk.SetFont("s9 Bold", "Microsoft YaHei UI")
        btnOk.OnEvent("Click", (*) => aGui.Destroy())
        
        aGui.Show("w328 h105 Center")
    }

    static CompareVersion(v1, v2) {
        a1 := StrSplit(v1, "."), a2 := StrSplit(v2, ".")
        maxLen := Max(a1.Length, a2.Length)
        Loop maxLen {
            n1 := (A_Index <= a1.Length) ? Integer(a1[A_Index]) : 0
            n2 := (A_Index <= a2.Length) ? Integer(a2[A_Index]) : 0
            if (n1 > n2)
                return 1
            if (n1 < n2)
                return -1
        }
        return 0
    }

    static ParseJson(jsonStr) {
        res := Map()
        if RegExMatch(jsonStr, 's)\"version\"\s*:\s*\"([^\"]+)\"', &m)
            res["version"] := m[1]
        if RegExMatch(jsonStr, 's)\"changelog\"\s*:\s*\"([^\"]+)\"', &m)
            res["changelog"] := StrReplace(m[1], "\n", "`n")
        
        files := []
        if RegExMatch(jsonStr, 's)\"files\"\s*:\s*\[(.*?)\]', &mFiles) {
            pos := 1
            while RegExMatch(mFiles[1], '\"([^\"]+)\"', &mItem, pos) {
                files.Push(mItem[1])
                pos := mItem.Pos + mItem.Len
            }
        }
        res["files"] := files
        return res
    }

    static GetModalHTML() {
        return '
        (
        <!DOCTYPE html>
        <html>
        <head>
            <meta http-equiv="X-UA-Compatible" content="IE=edge" />
            <meta charset="utf-8" />
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; }
                html, body { width: 100%; height: 100%; overflow: hidden; background-color: #FFFFFF; color: #18181B; user-select: none; }
                
                .modal-container {
                    padding: 18px 22px;
                    height: 100%;
                    box-sizing: border-box;
                }

                .title-row { font-size: 17px; font-weight: 900; color: #0066CC; margin-bottom: 2px; }
                .ver-row { font-size: 14px; font-weight: 800; color: #10B981; margin-bottom: 8px; }
                .ver-row span { font-size: 12px; font-weight: 500; color: #64748B; margin-left: 4px; }
                
                .sec-title { font-size: 12.5px; font-weight: 800; color: #334155; margin-bottom: 6px; }

                .log-card-container {
                    position: relative;
                    width: 100%;
                    height: 105px;
                    background-color: #F8FAFC;
                    border: 1.5px solid #84CC16;
                    border-radius: 10px;
                    padding: 2px;
                    box-sizing: border-box;
                    overflow: hidden;
                }

                .log-scroll-viewport {
                    width: calc(100% + 22px);
                    height: 100%;
                    overflow-y: scroll;
                    overflow-x: hidden;
                    padding-right: 28px;
                    padding-left: 10px;
                    padding-top: 8px;
                    padding-bottom: 8px;
                    font-size: 12.5px;
                    line-height: 1.55;
                    color: #334155;
                    font-weight: 600;
                    -ms-overflow-style: none;
                    box-sizing: border-box;
                }
                .log-scroll-viewport::-webkit-scrollbar {
                    display: none;
                    width: 0;
                    height: 0;
                }

                .capsule-track {
                    position: absolute;
                    top: 5px;
                    bottom: 5px;
                    right: 6px;
                    width: 8px;
                    background-color: #D9DCD2;
                    border-radius: 8px;
                    pointer-events: none;
                    z-index: 100;
                }

                .capsule-thumb {
                    position: absolute;
                    top: 0;
                    left: 1px;
                    width: 6px;
                    height: 32px;
                    background-color: #84CC16;
                    border-radius: 6px;
                    transition: top 0.05s ease-out;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.12);
                }

                .tips-text {
                    text-align: center;
                    font-size: 11.5px;
                    font-weight: 600;
                    color: #64748B;
                    margin-top: 10px;
                    margin-bottom: 8px;
                }

                .btn-download {
                    width: 100%;
                    height: 38px;
                    background-color: #D4F658;
                    color: #1A2E05;
                    border: 1px solid #C4EC44;
                    border-radius: 9px;
                    font-size: 13.5px;
                    font-weight: 800;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 0.2s ease;
                }
                .btn-download:hover {
                    background-color: #C8EA2D;
                    box-shadow: 0 3px 10px rgba(212, 246, 88, 0.45);
                }
            </style>
        </head>
        <body>
            <div class="modal-container">
                <div class="title-row">🚀 发现新版本</div>
                <div class="ver-row">v{{LATEST_VER}} <span>(当前版本: v{{CURRENT_VER}})</span></div>
                <div class="sec-title">📋 更新内容:</div>
                
                <div class="log-card-container">
                    <div class="capsule-track"><div class="capsule-thumb" id="logThumb"></div></div>
                    <div class="log-scroll-viewport" id="logViewport" onscroll="updateLogScroll()">
                        {{CHANGELOG}}
                    </div>
                </div>

                <div class="tips-text" id="tipsText">发现新功能特性，建议立即更新体验</div>
                <button class="btn-download" id="btnUpdate" onclick="triggerDownload()">🚀 立即下载并更新</button>
            </div>

            <script>
                function updateLogScroll() {
                    var vp = document.getElementById("logViewport");
                    var thumb = document.getElementById("logThumb");
                    if (!vp || !thumb) return;

                    var scrollHeight = vp.scrollHeight - vp.clientHeight;
                    if (scrollHeight <= 0) {
                        thumb.style.display = "none";
                        return;
                    }
                    thumb.style.display = "block";

                    var maxTravel = (vp.clientHeight - 10) - 32;
                    if (maxTravel < 10) maxTravel = 10;
                    var progress = vp.scrollTop / scrollHeight;
                    thumb.style.top = (progress * maxTravel) + "px";
                }

                function triggerDownload() {
                    var btn = document.getElementById("btnUpdate");
                    btn.style.display = "none";
                    var tip = document.getElementById("tipsText");
                    tip.innerText = "正在准备下载更新组件...";
                    window.ahk_download();
                }

                function setProgress(msg) {
                    var tip = document.getElementById("tipsText");
                    if (tip) tip.innerText = msg;
                }

                function setFailed(msg) {
                    var tip = document.getElementById("tipsText");
                    if (tip) tip.innerText = msg;
                    var btn = document.getElementById("btnUpdate");
                    if (btn) {
                        btn.style.display = "block";
                        btn.innerText = "重试更新";
                    }
                }

                window.onload = function() {
                    setTimeout(updateLogScroll, 30);
                };
            </script>
        </body>
        </html>
        )'
    }
}