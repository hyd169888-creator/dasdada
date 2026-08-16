#Requires AutoHotkey v2.0

; ==============================================================================
; 注册底层窗口消息拦截：禁止移动、拦截主程序点击与关闭、联动最小化
; ==============================================================================
OnMessage(0x00A1, WM_NCLBUTTONDOWN_LOCK, 2)
OnMessage(0x0112, WM_SYSCOMMAND_LOCK, 2)
OnMessage(0x0201, WM_LBUTTONDOWN_LOCK, 2)

WM_NCLBUTTONDOWN_LOCK(wParam, lParam, msg, hwnd) {
    mainHwnd := (IsSet(SettingsUI) && SettingsUI.gui) ? SettingsUI.gui.Hwnd : 0
    if (AppUpdater.gui && (hwnd == AppUpdater.gui.Hwnd || hwnd == mainHwnd)) {
        if (wParam == 2) {
            try AppUpdater.TriggerButtonShake()
            return 0
        }
    }
}

WM_SYSCOMMAND_LOCK(wParam, lParam, msg, hwnd) {
    cmd := wParam & 0xFFF0
    mainHwnd := (IsSet(SettingsUI) && SettingsUI.gui) ? SettingsUI.gui.Hwnd : 0
    
    if (AppUpdater.gui && (hwnd == AppUpdater.gui.Hwnd || hwnd == mainHwnd)) {
        if (cmd == 0xF010 || cmd == 0xF060 || cmd == 0xF030) {
            try AppUpdater.TriggerButtonShake()
            return 0
        }

        if (cmd == 0xF020) {
            try {
                if (hwnd == mainHwnd) {
                    WinMinimize("ahk_id " . AppUpdater.gui.Hwnd)
                } else if (hwnd == AppUpdater.gui.Hwnd && mainHwnd) {
                    WinMinimize("ahk_id " . mainHwnd)
                }
            }
        }
    }
}

WM_LBUTTONDOWN_LOCK(wParam, lParam, msg, hwnd) {
    mainHwnd := (IsSet(SettingsUI) && SettingsUI.gui) ? SettingsUI.gui.Hwnd : 0
    if (AppUpdater.gui && hwnd == mainHwnd) {
        try AppUpdater.TriggerButtonShake()
        return 0
    }
}

class AppUpdater {
    static defaultVersion := "1.0.0"
    static versionFile    := A_ScriptDir . "\version.txt"
    static gui            := 0
    static wbInst         := 0
    
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
        SetTimer(() => this.AsyncCheck(silent), -50)
    }

    static AsyncCheck(silent) {
        url := this.rawUrlBase . this.githubUser . "/" . this.githubRepo . "/" . this.branch . "/version.json?t=" . A_TickCount
        curVer := this.GetCurrentVersion()
        
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", url, true)
            http.SetTimeouts(500, 500, 800, 1000)
            http.Send()
            http.WaitForResponse(1.0)
            
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

    static ShowUpdateModal(latestVer, currentVer, changelog, files) {
        if (this.gui != 0) {
            this.gui.Show("w410 h390 Center")
            return
        }

        opt := "-Caption"
        if (IsSet(SettingsUI) && SettingsUI.gui)
            opt .= " +Owner" . SettingsUI.gui.Hwnd

        uGui := Gui(opt, "系统更新")
        uGui.MarginX := 0
        uGui.MarginY := 0
        uGui.BackColor := "FFFFFF"
        
        wbCtrl := uGui.AddActiveX("x0 y0 w410 h390", "Shell.Explorer")
        this.wbInst := wbCtrl.Value
        this.wbInst.Silent := true
        this.wbInst.Navigate("about:blank")
        while this.wbInst.ReadyState != 4
            Sleep(10)

        html := this.GetModalHTML()
        html := StrReplace(html, "{{LATEST_VER}}", latestVer)
        html := StrReplace(html, "{{CURRENT_VER}}", currentVer)

        htmlLog := StrReplace(changelog, "`n", "<br>")
        htmlLog := StrReplace(htmlLog, "\n", "<br>")
        html := StrReplace(html, "{{CHANGELOG}}", htmlLog)

        doc := this.wbInst.Document
        doc.open()
        doc.write(html)
        doc.close()

        doc.parentWindow.ahk_download := () => this.StartDownload(uGui, doc, files, latestVer)

        this.gui := uGui
        uGui.Show("w410 h390 Center")
    }

    static TriggerButtonShake() {
        try {
            if (this.wbInst && this.wbInst.Document && this.wbInst.Document.parentWindow) {
                this.wbInst.Document.parentWindow.shakeButton()
            }
        }
    }

    ; 实时动态进度下载核心逻辑
    static StartDownload(uGui, doc, files, newVer) {
        if (files.Length == 0) {
            try doc.parentWindow.setProgress(100, "⚠️ 更新列表中没有待下载的文件")
            return
        }

        totalFiles := files.Length
        successCount := 0

        for index, fileName in files {
            percentStart := Round(((index - 1) / totalFiles) * 100)
            percentEnd := Round((index / totalFiles) * 100)
            
            try doc.parentWindow.setProgress(percentStart, "正在下载 (" . index . "/" . totalFiles . "): " . fileName)
            
            fileUrl := this.rawUrlBase . this.githubUser . "/" . this.githubRepo . "/" . this.branch . "/" . fileName
            localPath := A_ScriptDir . "\" . fileName

            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.Open("GET", fileUrl, true)
                http.Send()

                startTime := A_TickCount
                while (!http.WaitForResponse(0.05)) {
                    elapsed := A_TickCount - startTime
                    ; 实时平滑推进子进度，防止假进度或卡死
                    subProgress := percentStart + Round((percentEnd - percentStart) * Min(elapsed / 1500, 0.9))
                    try doc.parentWindow.setProgress(subProgress, "正在下载 (" . index . "/" . totalFiles . "): " . fileName)
                }

                if (http.Status == 200) {
                    fileObj := FileOpen(localPath, "w", "UTF-8")
                    fileObj.Write(http.ResponseText)
                    fileObj.Close()
                    successCount++
                    try doc.parentWindow.setProgress(percentEnd, "已完成: " . fileName)
                }
            } catch {
                continue
            }
        }

        if (successCount > 0) {
            this.SaveCurrentVersion(newVer)
            try doc.parentWindow.setProgress(100, "✅ 升级至 v" . newVer . " 成功！正在重启...")
            Sleep(800)
            uGui.Destroy()
            this.gui := 0
            this.wbInst := 0
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
                    padding: 16px 22px;
                    height: 100%;
                    box-sizing: border-box;
                    display: flex;
                    flex-direction: column;
                    justify-content: space-between;
                }

                .badge-wrapper {
                    text-align: center;
                    margin-bottom: 4px;
                }
                .badge {
                    display: inline-block;
                    background-color: #18181B;
                    color: #D8FA63;
                    font-size: 11px;
                    font-weight: 800;
                    padding: 5px 16px;
                    border-radius: 20px;
                    letter-spacing: 0.8px;
                    box-shadow: 0 2px 6px rgba(0,0,0,0.15);
                }

                .title-row { font-size: 18px; font-weight: 900; color: #18181B; margin-bottom: 2px; }
                .ver-row { font-size: 13.5px; font-weight: 800; color: #10B981; margin-bottom: 6px; }
                .ver-row span { font-size: 12px; font-weight: 500; color: #64748B; margin-left: 4px; }
                
                .sec-title { font-size: 12px; font-weight: 800; color: #334155; margin-bottom: 4px; }

                .log-card-container {
                    position: relative;
                    width: 100%;
                    height: 125px;
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
                    font-size: 12px;
                    line-height: 1.5;
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

                /* 横向胶囊动态进度条样式 */
                .progress-container {
                    margin-top: 4px;
                    margin-bottom: 4px;
                }
                .progress-track {
                    position: relative;
                    width: 100%;
                    height: 10px;
                    background-color: #D9DCD2;
                    border-radius: 10px;
                    overflow: hidden;
                    margin-bottom: 6px;
                }
                .progress-thumb {
                    position: absolute;
                    top: 0;
                    left: 0;
                    height: 100%;
                    width: 0%;
                    background-color: #84CC16;
                    border-radius: 10px;
                    transition: width 0.15s ease-out;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.12);
                }

                .tips-text {
                    text-align: center;
                    font-size: 11px;
                    font-weight: 600;
                    color: #64748B;
                }

                .btn-download {
                    width: 100%;
                    height: 40px;
                    background-color: #D4F658;
                    color: #1A2E05;
                    border: 1px solid #C4EC44;
                    border-radius: 10px;
                    font-size: 13.5px;
                    font-weight: 800;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 0.2s ease;
                    margin-bottom: 2px;
                }
                .btn-download:hover {
                    background-color: #C8EA2D;
                    box-shadow: 0 3px 10px rgba(212, 246, 88, 0.45);
                }

                @keyframes shakeAnim {
                    0% { transform: translateX(0); }
                    20% { transform: translateX(-6px); }
                    40% { transform: translateX(6px); }
                    60% { transform: translateX(-4px); }
                    80% { transform: translateX(4px); }
                    100% { transform: translateX(0); }
                }
                .shake {
                    animation: shakeAnim 0.4s ease-in-out;
                    background-color: #FACC15 !important;
                }
            </style>
        </head>
        <body>
            <div class="modal-container">
                <div class="badge-wrapper">
                    <div class="badge">⚡ LIVE INTELLIGENT UPDATER</div>
                </div>
                <div>
                    <div class="title-row">发现新版本可用</div>
                    <div class="ver-row">v{{LATEST_VER}} <span>(当前版本: v{{CURRENT_VER}})</span></div>
                    <div class="sec-title">📦 更新日志与功能变更:</div>
                </div>
                
                <div class="log-card-container">
                    <div class="capsule-track"><div class="capsule-thumb" id="logThumb"></div></div>
                    <div class="log-scroll-viewport" id="logViewport" onscroll="updateLogScroll()">
                        {{CHANGELOG}}
                    </div>
                </div>

                <div class="progress-container">
                    <div class="progress-track">
                        <div class="progress-thumb" id="progressThumb" style="width: 0%;"></div>
                    </div>
                    <div class="tips-text" id="tipsText">发现新功能特性，建议立即更新体验</div>
                </div>

                <button class="btn-download" id="btnUpdate" onclick="triggerDownload()">🚀 立即下载并应用更新</button>
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

                function shakeButton() {
                    var btn = document.getElementById("btnUpdate");
                    if (btn) {
                        btn.classList.remove("shake");
                        void btn.offsetWidth;
                        btn.classList.add("shake");
                    }
                }

                function triggerDownload() {
                    var btn = document.getElementById("btnUpdate");
                    btn.style.display = "none";
                    var tip = document.getElementById("tipsText");
                    tip.innerText = "正在准备下载更新组件...";
                    window.ahk_download();
                }

                function setProgress(percent, msg) {
                    var thumb = document.getElementById("progressThumb");
                    if (thumb) {
                        thumb.style.width = percent + "%";
                    }
                    var tip = document.getElementById("tipsText");
                    if (tip) {
                        tip.innerText = msg;
                    }
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