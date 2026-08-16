#Requires AutoHotkey v2.0

class AppUpdater {
    ; GitHub 仓库地址配置
    static rawBaseUrl := "https://ghproxy.net/https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static directRawUrl := "https://raw.githubusercontent.com/hyd169888-creator/dasdada/main"
    static versionFile := A_ScriptDir . "\version.txt"
    static gui := 0
    static wb := 0
    static doc := 0
    static mainHwnd := 0
    static isUpdating := false
    static isHooked := false
    static curRemoteVer := ""
    static curFileList := []

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

    ; 防缓存读取 version.json 文本
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

    ; 二进制流下载文件 (彻底杜绝编码二次转码损坏问题)
    static DownloadBinaryFile(url, destPath) {
        reqUrl := url . (InStr(url, "?") ? "&" : "?") . "_t=" . A_TickCount
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.SetTimeouts(5000, 5000, 15000, 15000)
            http.Open("GET", reqUrl, false)
            http.SetRequestHeader("Pragma", "no-cache")
            http.SetRequestHeader("Cache-Control", "no-cache, no-store, must-revalidate")
            http.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            http.Send()
            if (http.Status == 200) {
                stream := ComObject("ADODB.Stream")
                stream.Type := 1 ; 二进制模式 adTypeBinary
                stream.Open()
                stream.Write(http.ResponseBody)
                stream.SaveToFile(destPath, 2) ; 覆盖写入 adSaveCreateOverWrite
                stream.Close()
                return true
            }
        } catch {
        }
        return false
    }

    ; 窗口抖动提醒
    static ShakeModal() {
        if (!this.gui || !WinExist("ahk_id " . this.gui.Hwnd))
            return
        
        try {
            WinActivate("ahk_id " . this.gui.Hwnd)
            this.gui.GetPos(&gx, &gy, &gw, &gh)
            Loop 3 {
                this.gui.Move(gx - 8, gy)
                Sleep 25
                this.gui.Move(gx + 8, gy)
                Sleep 25
            }
            this.gui.Move(gx, gy)
        }
    }

    ; 拦截移动/关闭消息
    static _OnWmSysCommand(wParam, lParam, msg, hwnd) {
        if (AppUpdater.gui && (hwnd == AppUpdater.gui.Hwnd || hwnd == AppUpdater.mainHwnd)) {
            cmd := wParam & 0xFFF0
            if (cmd == 0xF010) ; 拦截移动
                return 0
            if (cmd == 0xF060) { ; 拦截关闭
                AppUpdater.ShakeModal()
                return 0
            }
        }
    }

    static _OnWmNcLButtonDown(wParam, lParam, msg, hwnd) {
        if (AppUpdater.gui && (hwnd == AppUpdater.gui.Hwnd || hwnd == AppUpdater.mainHwnd)) {
            if (wParam == 2 || wParam == 20) {
                AppUpdater.ShakeModal()
                return 0
            }
        }
    }

    ; 优先级握手：等待主界面完全渲染就绪后立即触发检查
    static StartAutoCheck() {
        SetTimer(() => this._WaitForMainAndCheck(), -60)
    }

    static _WaitForMainAndCheck() {
        Loop 25 {
            if (hwnd := WinExist("AI 智能打字翻译 - 设置中心")) {
                if DllCall("IsWindowVisible", "Ptr", hwnd) {
                    this.mainHwnd := hwnd
                    break
                }
            }
            Sleep(80)
        }
        this._DoCheck(true)
    }

    ; 手动检查入口
    static Check(isSilent := false) {
        SetTimer(() => this._DoCheck(isSilent), -100)
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

        changelog := StrReplace(changelog, "\n", "`n")
        changelog := StrReplace(changelog, '\"', '"')

        if (remoteVer != "" && this.CompareVersions(remoteVer, localVer) > 0) {
            this.ShowUpdateDialog(remoteVer, localVer, changelog, fileList)
        } else if (!isSilent) {
            MsgBox("当前已是最新版本 (v" . localVer . ")，无需更新。", "检查更新", "Iconi")
        }
    }

    ; HTML 字符安全转义
    static HtmlEscape(str) {
        str := StrReplace(str, "&", "&amp;")
        str := StrReplace(str, "<", "&lt;")
        str := StrReplace(str, ">", "&gt;")
        str := StrReplace(str, '"', '&quot;')
        return str
    }

    ; 供 Web 按钮直接调用的触发函数
    static TriggerUpdateFromWeb() {
        SetTimer(() => this.PerformUpdate(this.curRemoteVer, this.curFileList), -10)
    }

    ; 构建现代质感更新弹窗
    static ShowUpdateDialog(remoteVer, localVer, changelog, fileList) {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.ShakeModal()
            return
        }

        this.curRemoteVer := remoteVer
        this.curFileList := fileList

        if (!this.mainHwnd || !WinExist("ahk_id " . this.mainHwnd)) {
            this.mainHwnd := WinExist("AI 智能打字翻译 - 设置中心")
        }

        ; 注册全局防拖动与拦截器
        if (!this.isHooked) {
            OnMessage(0x0112, (wp, lp, msg, hwnd) => this._OnWmSysCommand(wp, lp, msg, hwnd))
            OnMessage(0x00A1, (wp, lp, msg, hwnd) => this._OnWmNcLButtonDown(wp, lp, msg, hwnd))
            this.isHooked := true
        }

        ; 父子属主关系 (+Owner)
        ownerOpt := this.mainHwnd ? " +Owner" . this.mainHwnd : ""
        g := Gui(ownerOpt . " -MaximizeBox -MinimizeBox -SysMenu +Border +ToolWindow +OwnDialogs", "系统更新")
        g.BackColor := "0xF8FAF5"
        g.MarginX := 0
        g.MarginY := 0
        this.gui := g

        ; 禁用主界面点击交互
        if (this.mainHwnd) {
            WinSetEnabled(0, "ahk_id " . this.mainHwnd)
        }

        ; 嵌入 Web 渲染容器
        wbCtl := g.Add("ActiveX", "w390 h430", "Shell.Explorer")
        this.wb := wbCtl.Value
        this.wb.silent := true
        this.wb.Navigate("about:blank")
        while (this.wb.ReadyState != 4)
            Sleep(10)

        safeLog := this.HtmlEscape(changelog)

        ; HTML 模板（内置横向胶囊动态进度条）
        htmlTemplate := "
        (
        <!DOCTYPE html>
        <html>
        <head>
        <meta http-equiv="X-UA-Compatible" content="IE=edge">
        <meta charset="utf-8">
        <style>
            * {
                box-sizing: border-box;
                margin: 0;
                padding: 0;
                user-select: none;
                -webkit-user-select: none;
            }
            body {
                background-color: #F8FAF5;
                font-family: -apple-system, "Microsoft YaHei UI", "Segoe UI", sans-serif;
                padding: 20px 22px;
                overflow: hidden;
                color: #18181B;
            }
            .badge-container {
                display: flex;
                justify-content: center;
                width: 100%;
                margin-bottom: 2px;
            }
            .badge-wrap {
                display: inline-flex;
                align-items: center;
                justify-content: center;
                background: #18181B;
                color: #D8FA63;
                padding: 4px 12px;
                border-radius: 20px;
                font-size: 11px;
                font-weight: 700;
                letter-spacing: 0.5px;
            }
            .title {
                font-size: 19px;
                font-weight: 800;
                color: #0F172A;
                margin-top: 8px;
            }
            .version-bar {
                margin-top: 4px;
                font-size: 13px;
            }
            .ver-tag {
                color: #15803D;
                font-weight: 800;
                font-size: 14px;
                margin-right: 6px;
            }
            .ver-old {
                color: #64748B;
                font-size: 12px;
            }
            .section-label {
                font-size: 12px;
                font-weight: 700;
                color: #334155;
                margin-top: 12px;
                margin-bottom: 6px;
            }
            .log-box-wrapper {
                position: relative;
                background: #FFFFFF;
                border: 1.5px solid #E2E8F0;
                border-radius: 10px;
                height: 116px;
                padding: 10px 12px;
                overflow: hidden;
            }
            .log-content {
                height: 100%;
                width: 100%;
                padding-right: 14px;
                overflow-y: hidden;
                font-size: 12px;
                line-height: 1.6;
                color: #334155;
                white-space: pre-wrap;
                word-break: break-all;
            }
            .custom-scrollbar-track {
                position: absolute;
                top: 8px;
                bottom: 8px;
                right: 6px;
                width: 5px;
                background: #F1F5F9;
                border-radius: 4px;
            }
            .custom-scrollbar-thumb {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 36px;
                background: #84cc16;
                border-radius: 4px;
                cursor: pointer;
                transition: background 0.15s;
            }
            .custom-scrollbar-thumb:hover {
                background: #65a30d;
            }
            .notice-text {
                font-size: 11px;
                color: #94A3B8;
                text-align: center;
                margin-top: 12px;
            }
            .btn-update {
                width: 100%;
                height: 42px;
                margin-top: 10px;
                background-color: #D8FA63;
                color: #18181B;
                border: 1px solid #C4E840;
                border-radius: 10px;
                font-size: 13px;
                font-weight: 800;
                cursor: pointer;
                display: flex;
                align-items: center;
                justify-content: center;
                box-shadow: 0 4px 12px rgba(216, 250, 99, 0.35);
                outline: none;
            }
            .btn-update:hover {
                background-color: #CBF048;
            }

            /* 横向胶囊进度条组件 */
            .progress-container {
                display: none;
                width: 100%;
                margin-top: 12px;
            }
            .progress-track {
                width: 100%;
                height: 10px;
                background: #F1F5F9;
                border: 1px solid #E2E8F0;
                border-radius: 20px;
                overflow: hidden;
                position: relative;
            }
            .progress-fill {
                width: 0%;
                height: 100%;
                background: linear-gradient(90deg, #84cc16 0%, #D8FA63 100%);
                border-radius: 20px;
                transition: width 0.28s cubic-bezier(0.4, 0, 0.2, 1);
            }
            .progress-meta {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-top: 6px;
                font-size: 11px;
                font-weight: 700;
            }
            .progress-status {
                color: #15803D;
            }
            .progress-pct {
                color: #64748B;
            }
        </style>
        </head>
        <body>
            <div class="badge-container">
                <div class="badge-wrap">⚡ LIVE INTELLIGENT UPDATER</div>
            </div>
            <div class="title">发现新版本可用</div>
            <div class="version-bar">
                <span class="ver-tag">v{{REMOTE_VER}}</span>
                <span class="ver-old">(当前版本: v{{LOCAL_VER}})</span>
            </div>
            
            <div class="section-label">📦 更新日志与功能变更：</div>
            <div class="log-box-wrapper" id="logWrapper">
                <div class="log-content" id="logContent">{{SAFE_LOG}}</div>
                <div class="custom-scrollbar-track" id="scrollTrack">
                    <div class="custom-scrollbar-thumb" id="scrollThumb"></div>
                </div>
            </div>
            
            <div class="notice-text">⚠️ 此版本包含重要功能重构，必须完成更新后方可使用</div>
            
            <button id="btnUpdate" class="btn-update" onclick="window.ahkBridge.TriggerUpdate()">
                🚀 立即下载并应用更新
            </button>
            
            <!-- 胶囊进度条 -->
            <div id="progressContainer" class="progress-container">
                <div class="progress-track">
                    <div id="progressFill" class="progress-fill"></div>
                </div>
                <div class="progress-meta">
                    <span id="progressStatus" class="progress-status">正在连接更新通道...</span>
                    <span id="progressPct" class="progress-pct">0%</span>
                </div>
            </div>

            <script>
                function initScroll() {
                    var content = document.getElementById('logContent');
                    var track = document.getElementById('scrollTrack');
                    var thumb = document.getElementById('scrollThumb');
                    var wrapper = document.getElementById('logWrapper');
                    if (!content || !track || !thumb || !wrapper) return;

                    function updateThumb() {
                        var scrollRatio = content.clientHeight / content.scrollHeight;
                        if (scrollRatio >= 1) {
                            thumb.style.height = '100%';
                            thumb.style.top = '0px';
                        } else {
                            var trackH = track.clientHeight;
                            var thumbH = Math.max(24, trackH * scrollRatio);
                            thumb.style.height = thumbH + 'px';
                            var maxTop = trackH - thumbH;
                            var curTop = (content.scrollTop / (content.scrollHeight - content.clientHeight)) * maxTop;
                            thumb.style.top = Math.min(Math.max(0, curTop), maxTop) + 'px';
                        }
                    }

                    function onWheel(e) {
                        e = e || window.event;
                        var delta = e.deltaY !== undefined ? e.deltaY : (e.wheelDelta ? -e.wheelDelta : 0);
                        content.scrollTop += (delta > 0 ? 25 : -25);
                        updateThumb();
                        if (e.preventDefault) e.preventDefault();
                        return false;
                    }

                    if (wrapper.addEventListener) {
                        wrapper.addEventListener('wheel', onWheel, false);
                        wrapper.addEventListener('mousewheel', onWheel, false);
                        wrapper.addEventListener('DOMMouseScroll', onWheel, false);
                    } else {
                        wrapper.attachEvent('onmousewheel', onWheel);
                    }

                    var isDragging = false;
                    var startY = 0;
                    var startTop = 0;

                    thumb.onmousedown = function(e) {
                        e = e || window.event;
                        isDragging = true;
                        startY = e.clientY;
                        startTop = parseInt(thumb.style.top || 0);
                        document.onmousemove = function(e) {
                            if (!isDragging) return;
                            e = e || window.event;
                            var delta = e.clientY - startY;
                            var trackH = track.clientHeight;
                            var thumbH = thumb.offsetHeight;
                            var maxTop = trackH - thumbH;
                            var newTop = Math.min(Math.max(0, startTop + delta), maxTop);
                            thumb.style.top = newTop + 'px';
                            var pct = maxTop > 0 ? (newTop / maxTop) : 0;
                            content.scrollTop = pct * (content.scrollHeight - content.clientHeight);
                        };
                        document.onmouseup = function() {
                            isDragging = false;
                            document.onmousemove = null;
                            document.onmouseup = null;
                        };
                        return false;
                    };

                    updateThumb();
                    setTimeout(updateThumb, 120);
                }
                window.onload = initScroll;
            </script>
        </body>
        </html>
        )"

        html := StrReplace(htmlTemplate, "{{REMOTE_VER}}", remoteVer)
        html := StrReplace(html, "{{LOCAL_VER}}", localVer)
        html := StrReplace(html, "{{SAFE_LOG}}", safeLog)

        this.doc := this.wb.Document
        this.doc.open()
        this.doc.write(html)
        this.doc.close()

        ; 注册 JS 桥接对象
        bridge := {
            TriggerUpdate: (*) => AppUpdater.TriggerUpdateFromWeb()
        }
        this.doc.parentWindow.ahkBridge := bridge

        ; 居中显示于主程序上方
        if (this.mainHwnd) {
            WinGetPos(&mx, &my, &mw, &mh, "ahk_id " . this.mainHwnd)
            dx := mx + (mw - 390) // 2
            dy := my + (mh - 430) // 2
            g.Show("x" . dx . " y" . dy . " w390 h430")
        } else {
            g.Show("w390 h430 Center")
        }
        
        WinActivate("ahk_id " . g.Hwnd)
    }

    ; 更新前端胶囊进度条与状态
    static UpdateProgressUI(pct, statusText, isError := false) {
        try {
            bBtn := this.doc.getElementById("btnUpdate")
            pCont := this.doc.getElementById("progressContainer")
            pFill := this.doc.getElementById("progressFill")
            pStatus := this.doc.getElementById("progressStatus")
            pPct := this.doc.getElementById("progressPct")

            if (isError) {
                bBtn.style.display := "flex"
                pCont.style.display := "none"
                MsgBox(statusText, "更新失败", "Iconx")
                return
            }

            bBtn.style.display := "none"
            pCont.style.display := "block"
            pFill.style.width := pct . "%"
            pPct.innerText := pct . "%"
            pStatus.innerText := statusText
        }
    }

    ; 执行更新与组件覆写 (二进制安全下载)
    static PerformUpdate(remoteVer, fileList) {
        if (this.isUpdating)
            return
        this.isUpdating := true

        this.UpdateProgressUI(5, "正在建立高速通道...")

        successCount := 0
        tempDir := A_ScriptDir . "\~temp_update"
        if !DirExist(tempDir)
            DirCreate(tempDir)

        totalFiles := fileList.Length

        for idx, fileName in fileList {
            ; 动态计算真实百分比
            currentPct := Integer(10 + ((idx - 0.5) / totalFiles) * 80)
            this.UpdateProgressUI(currentPct, "正在下载组件 (" . idx . "/" . totalFiles . ")...")

            tempPath := tempDir . "\" . fileName
            if FileExist(tempPath)
                FileDelete(tempPath)

            ; 优先代理，失败直连 (二进制模式)
            fileUrl := this.rawBaseUrl . "/" . fileName
            ok := this.DownloadBinaryFile(fileUrl, tempPath)
            
            if (!ok) {
                fileUrl := this.directRawUrl . "/" . fileName
                ok := this.DownloadBinaryFile(fileUrl, tempPath)
            }

            if (ok && FileExist(tempPath) && FileGetSize(tempPath) > 0) {
                successCount++
            }

            finishPct := Integer(10 + (idx / totalFiles) * 80)
            this.UpdateProgressUI(finishPct, "正在同步组件 (" . idx . "/" . totalFiles . ")...")
            Sleep(60) ; 微量缓冲让平滑动画更加丝滑
        }

        if (successCount >= totalFiles) {
            this.UpdateProgressUI(95, "正在应用组件...")

            ; 替换实际脚本
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

            this.UpdateProgressUI(100, "✅ 更新完成，正在重启...")
            Sleep(500)

            ; 恢复主窗口
            if (this.mainHwnd && WinExist("ahk_id " . this.mainHwnd))
                WinSetEnabled(1, "ahk_id " . this.mainHwnd)

            ; 重启程序
            if A_IsCompiled {
                Run('"' . A_ScriptFullPath . '"')
            } else {
                Run('"' . A_AhkPath . '" "' . (FileExist(A_ScriptDir . "\Main.ahk") ? A_ScriptDir . "\Main.ahk" : A_ScriptFullPath) . '"')
            }
            ExitApp()
        } else {
            this.isUpdating := false
            this.UpdateProgressUI(0, "部分组件下载失败，请检查网络", true)
        }
    }
}