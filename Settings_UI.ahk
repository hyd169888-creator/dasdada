#Requires AutoHotkey v2.0

class SettingsUI {
    static defaultConfig := Map(
        "source_lang", "auto",
        "target_lang", "en",
        "provider", "DeepSeek",
        "base_url", "https://api.deepseek.com/v1",
        "model", "deepseek-chat",
        "api_key", "",
        "hotkeys", Map("show_bar", "!y", "settings", "!s")
    )
    
    static configFile := A_ScriptDir . "\config.json"
    static gui := 0
    static wv := 0

    static _ParseJsonToMap(jsonStr) {
        return Map(
            "source_lang", RegExMatch(jsonStr, '"source_lang"\s*:\s*"([^"]+)"', &m1) ? m1[1] : "auto",
            "target_lang", RegExMatch(jsonStr, '"target_lang"\s*:\s*"([^"]+)"', &m2) ? m2[1] : "en",
            "provider", RegExMatch(jsonStr, '"provider"\s*:\s*"([^"]+)"', &m3) ? m3[1] : "DeepSeek",
            "base_url", RegExMatch(jsonStr, '"base_url"\s*:\s*"([^"]+)"', &m4) ? m4[1] : "https://api.deepseek.com/v1",
            "model", RegExMatch(jsonStr, '"model"\s*:\s*"([^"]+)"', &m5) ? m5[1] : "deepseek-chat",
            "api_key", RegExMatch(jsonStr, '"api_key"\s*:\s*"([^"]+)"', &m6) ? m6[1] : ""
        )
    }

    static _MapToJson(cfg) {
        return '{'
            . '"source_lang": "' . cfg["source_lang"] . '", '
            . '"target_lang": "' . cfg["target_lang"] . '", '
            . '"provider": "' . cfg["provider"] . '", '
            . '"base_url": "' . cfg["base_url"] . '", '
            . '"model": "' . cfg["model"] . '", '
            . '"api_key": "' . cfg["api_key"] . '"'
            . '}'
    }

    static LoadConfig() {
        if !FileExist(this.configFile) {
            this.SaveConfig(this.defaultConfig)
            return this.defaultConfig
        }
        try {
            content := FileRead(this.configFile, "UTF-8")
            if (Trim(content) == "")
                return this.defaultConfig
            return this._ParseJsonToMap(content)
        } catch {
            return this.defaultConfig
        }
    }

    static SaveConfig(cfgMap) {
        jsonStr := this._MapToJson(cfgMap)
        try {
            if FileExist(this.configFile)
                FileDelete(this.configFile)
            FileAppend(jsonStr, this.configFile, "UTF-8")
            return true
        } catch {
            return false
        }
    }

    static Show() {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.gui.Show()
            WinActivate("ahk_id " . this.gui.Hwnd)
            return
        }

        g := Gui("-MaximizeBox -MinimizeBox", "AI 智能打字翻译 - 设置中心")
        g.BackColor := "0xF5F6F2"
        g.MarginX := 0
        g.MarginY := 0
        this.gui := g

        wbCtl := g.Add("ActiveX", "w460 h735", "Shell.Explorer")
        this.wv := wbCtl.Value
        this.wv.silent := true
        this.wv.Navigate("about:blank")
        while (this.wv.ReadyState != 4)
            Sleep(10)

        cfg := this.LoadConfig()
        localVer := FileExist(A_ScriptDir . "\version.txt") ? Trim(FileRead(A_ScriptDir . "\version.txt", "UTF-8")) : "1.0.1"

        logoElement := '<img class="brand-avatar" src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0OCA0OCIgd2lkdGg9IjQ4IiBoZWlnaHQ9IjQ4Ij48cmVjdCB3aWR0aD0iNDgiIGhlaWdodD0iNDgiIHJ4PSIxMiIgZmlsbD0iIzZFRTdCNyIvPjxyZWN0IHg9IjYiIHk9IjgiIHdpZHRoPSIxNiIgaGVpZ2h0PSIxNCIgcng9IjQiIGZpbGw9IiNGRkZGRkYiLz48dGV4dCB4PSIxNCIgeT0iMTkiIGZvbnQtc2l6ZT0iMTEiIGZvbnQtZmFtaWx5PSJBcmlhbCwgc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjkwMCIgZmlsbD0iIzA2NUY0NiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+QTwvdGV4dD48cmVjdCB4PSIyNCIgeT0iOCIgd2lkdGg9IjE4IiBoZWlnaHQ9IjE0IiByeD0iNCIgZmlsbD0iI0ZGRkZGRiIvPjx0ZXh0IHg9IjMzIiB5PSIxOSIgZm9udC1zaXplPSIxMSIgZm9udC1mYW1pbHk9Ik1pY3Jvc29mdCBZYUhlaSwgc2Fucy1zZXJpZiIgZm9udC13ZWlnaHQ9IjkwMCIgZmlsbD0iIzA2NUY0NiIgdGV4dC1hbmNob3I9Im1pZGRsZSI+5paHPC90ZXh0PjxyZWN0IHg9IjgiIHk9IjI3IiB3aWR0aD0iMzIiIGhlaWdodD0iMTMiIHJ4PSIzIiBmaWxsPSIjMDY1RjQ2IiBmaWxsLW9wYWNpdHk9IjAuMTUiLz48cmVjdCB4PSIxMSIgeT0iMjkiIHdpZHRoPSI0IiBoZWlnaHQ9IjMiIHJ4PSIxIiBmaWxsPSIjMDY1RjQ2Ii8+PHJlY3QgeD0iMTciIHk9IjI5IiB3aWR0aD0iNCIgaGVpZ2h0PSIzIiByeD0iMSIgZmlsbD0iIzA2NUY0NiIvPjxyZWN0IHg9IjIzIiB5PSIyOSIgd2lkdGg9IjQiIGhlaWdodD0iMyIgcng9IjEiIGZpbGw9IiMwNjVGNDYiLz48cmVjdCB4PSIyOSIgeT0iMjkiIHdpZHRoPSI0IiBoZWlnaHQ9IjMiIHJ4PSIxIiBmaWxsPSIjMDY1RjQ2Ii8+PHJlY3QgeD0iMTMiIHk9IjM0IiB3aWR0aD0iMjIiIGhlaWdodD0iMyIgcng9IjEiIGZpbGw9IiMwNjVGNDYiLz48L3N2Zz4=" />'
        possibleLogos := [A_ScriptDir . "\config\logo.png", A_ScriptDir . "\config\logo.ico", A_ScriptDir . "\config\icon.png", A_ScriptDir . "\config\logo.jpg"]
        for p in possibleLogos {
            if FileExist(p) {
                logoElement := '<img class="brand-avatar" src="file:///' . StrReplace(p, "\", "/") . '" />'
                break
            }
        }

        html := this._BuildHtml(cfg, localVer, logoElement)
        doc := this.wv.Document
        doc.open()
        doc.write(html)
        doc.close()

        bridge := {
            SaveSettings: (sLang, tLang, prov, bUrl, mdl, key) => SettingsUI._OnSaveSettings(sLang, tLang, prov, bUrl, mdl, key),
            TestApi: (prov, bUrl, mdl, key) => SettingsUI._OnTestApi(prov, bUrl, mdl, key)
        }
        doc.parentWindow.ahkBridge := bridge

        g.OnEvent("Close", (*) => g.Hide())
        g.Show("w460 h735 Center")
    }

    static _OnSaveSettings(sLang, tLang, prov, bUrl, mdl, key) {
        cfg := this.LoadConfig()
        cfg["source_lang"] := sLang
        cfg["target_lang"] := tLang
        cfg["provider"] := prov
        cfg["base_url"] := bUrl
        cfg["model"] := mdl
        cfg["api_key"] := key

        if this.SaveConfig(cfg) {
            try this.wv.Document.parentWindow.showToast("✓", "配置保存成功", "全部配置已生效，可直接开始翻译")
        } else {
            try this.wv.Document.parentWindow.showToast("✕", "保存失败", "配置文件写入异常，请检查权限")
        }
    }

    static _OnTestApi(prov, bUrl, mdl, key) {
        if (key == "") {
            try this.wv.Document.parentWindow.showToast("!", "请先填写 API Key", "API Key 不能为空")
            return
        }
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(5000, 5000, 10000, 10000)
            req.Open("POST", bUrl . "/chat/completions", false)
            req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
            req.SetRequestHeader("Authorization", "Bearer " . key)
            req.Send('{"model":"' . mdl . '","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}')

            if (req.Status == 200) {
                this.wv.Document.parentWindow.showToast("✓", "API 探测成功", "模型响应正常，网络通道通畅")
            } else {
                this.wv.Document.parentWindow.showToast("✕", "连接失败 (" . req.Status . ")", "端点返回异常，请检查参数")
            }
        } catch as e {
            this.wv.Document.parentWindow.showToast("✕", "无法连接端点", "请检查网络、代理节点或 Base URL")
        }
    }

    static _BuildHtml(cfg, ver, logoElement) {
        sLang := cfg.Has("source_lang") ? cfg["source_lang"] : "auto"
        tLang := cfg.Has("target_lang") ? cfg["target_lang"] : "en"
        prov := cfg.Has("provider") ? cfg["provider"] : "DeepSeek"
        bUrl := cfg.Has("base_url") ? cfg["base_url"] : "https://api.deepseek.com/v1"
        mdl := cfg.Has("model") ? cfg["model"] : "deepseek-chat"
        key := cfg.Has("api_key") ? cfg["api_key"] : ""

        sMap := Map("auto", "自动识别 (中英双向智能互译)", "zh", "中文 (Chinese)", "en", "English (英语)", "ja", "日本語 (Japanese)", "ko", "한국어 (Korean)", "pl", "Polski (波兰语)")
        sText := sMap.Has(sLang) ? sMap[sLang] : sLang

        tMap := Map("en", "English (英语)", "zh", "中文 (Chinese)", "pl", "Polski (波兰语)", "ja", "日本語 (Japanese)", "ko", "한국어 (Korean)", "es", "Español (西班牙语)", "fr", "Français (法语)", "de", "Deutsch (德语)", "ru", "Русский (俄语)")
        tText := tMap.Has(tLang) ? tMap[tLang] : tLang

        pMap := Map(
            "Gemini", "Gemini (需魔法)",
            "OpenAI", "ChatGPT (需魔法)",
            "NVIDIA", "NVIDIA·免费满血模型 (需魔法)",
            "DeepSeek", "DeepSeek (官方直连·深度思考)",
            "Doubao", "豆包(ByteDance)",
            "Custom", "自定义API(OpenAI 协议兼容)"
        )
        pText := pMap.Has(prov) ? pMap[prov] : prov

        htmlTemplate := "<!DOCTYPE html>`n"
            . "<html>`n"
            . "<head>`n"
            . '    <meta http-equiv="X-UA-Compatible" content="IE=edge" />`n'
            . '    <meta charset="utf-8" />`n'
            . "    <style>`n"
            . '        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; }`n'
            . "        html, body { width: 100%; height: 100%; overflow: hidden; background-color: #F5F6F2; color: #18181B; user-select: none; }`n"
            . '        .container { padding: 16px 22px; position: relative; height: 100%; }`n'
            . '        .header-bar { display: table; width: 100%; margin-bottom: 12px; }`n'
            . '        .brand-left { display: table-cell; vertical-align: middle; }`n'
            . '        .brand-avatar { display: inline-block; width: 34px; height: 34px; border-radius: 8px; margin-right: 9px; vertical-align: middle; object-fit: contain; }`n'
            . '        .brand-title { display: inline-block; vertical-align: middle; }`n'
            . '        .brand-name { font-size: 13.5px; font-weight: 800; letter-spacing: 0.5px; color: #18181B; }`n'
            . '        .brand-sub { font-size: 11px; color: #71717A; }`n'
            . '        .pills-right { display: table-cell; vertical-align: middle; text-align: right; }`n'
            . '        .pill { display: inline-block; font-size: 12px; padding: 4px 13px; border-radius: 16px; color: #71717A; background: transparent; cursor: pointer; transition: all 0.2s; }`n'
            . '        .pill.active { background: #18181B; color: #FFFFFF; font-weight: 700; }`n'
            . '        .tag { font-size: 10.5px; font-weight: 800; letter-spacing: 0.8px; color: #6366F1; text-transform: uppercase; margin-bottom: 2px; }`n'
            . '        .main-title { font-size: 20px; font-weight: 900; line-height: 1.2; color: #18181B; margin-bottom: 3px; letter-spacing: -0.3px; }`n'
            . '        .sub-desc { font-size: 12px; color: #71717A; margin-bottom: 12px; }`n'
            . '        .card { background: #FFFFFF; border-radius: 14px; padding: 12px 16px; margin-bottom: 10px; border: 1px solid #E3E4DC; box-shadow: 0 1px 3px rgba(0,0,0,0.02); position: relative; }`n'
            . '        .card-header { font-size: 11.5px; font-weight: 800; letter-spacing: 0.6px; color: #71717A; text-transform: uppercase; margin-bottom: 9px; }`n'
            . '        .form-row { display: table; width: 100%; margin-bottom: 9px; position: relative; }`n'
            . '        .form-row:last-child { margin-bottom: 0; }`n'
            . '        .form-label { display: table-cell; width: 105px; font-size: 13px; font-weight: 700; color: #3F3F46; vertical-align: middle; }`n'
            . '        .form-field { display: table-cell; vertical-align: middle; position: relative; }`n'
            . '        .input-box { width: 100%; height: 35px; background-color: #F3F4EE !important; border: 1.5px solid #84CC16 !important; border-radius: 9px; padding: 0 12px; font-size: 13.5px; color: #18181B; outline: none; }`n'
            . '        .custom-select { position: relative; width: 100%; user-select: none; }`n'
            . '        .select-trigger { width: 100%; height: 35px; background-color: #F3F4EE !important; border: 1.5px solid #84CC16 !important; border-radius: 9px; padding: 0 12px; font-size: 13.5px; color: #18181B; display: flex; align-items: center; justify-content: space-between; cursor: pointer; outline: none; }`n'
            . '        .select-text { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; padding-right: 8px; }`n'
            . '        .select-arrow { width: 14px; height: 14px; flex-shrink: 0; fill: none; stroke: #84CC16; stroke-width: 2.4; stroke-linecap: round; stroke-linejoin: round; transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1); }`n'
            . '        .custom-select.open .select-arrow { transform: rotate(180deg); }`n'
            . '        .select-dropdown { position: absolute; top: calc(100% + 5px); left: 0; right: 0; height: 180px; background-color: #F3F4EE !important; border: 1.5px solid #84CC16 !important; border-radius: 11px; box-shadow: 0 12px 30px rgba(0, 0, 0, 0.1); padding: 4px; z-index: 10000; overflow: hidden; opacity: 0; visibility: hidden; transform: translateY(-6px) scale(0.98); transition: opacity 0.2s, transform 0.2s, visibility 0.2s; pointer-events: none; }`n'
            . '        .custom-select.open .select-dropdown { opacity: 1; visibility: visible; transform: translateY(0) scale(1); pointer-events: auto; }`n'
            . '        .select-scroll-viewport { width: calc(100% + 22px); height: 100%; overflow-y: scroll; overflow-x: hidden; padding-right: 28px; padding-left: 2px; padding-top: 2px; padding-bottom: 2px; }`n'
            . '        .select-scroll-viewport::-webkit-scrollbar { display: none; width: 0; height: 0; }`n'
            . '        .capsule-track { position: absolute; top: 5px; bottom: 5px; right: 6px; width: 9px; background-color: #D9DCD2; border-radius: 9px; pointer-events: none; z-index: 10002; }`n'
            . '        .capsule-thumb { position: absolute; top: 0; left: 1px; width: 7px; height: 36px; background-color: #84CC16; border-radius: 7px; transition: top 0.06s ease-out; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }`n'
            . '        .select-option { padding: 7px 9px; font-size: 13px; color: #27272A; border-radius: 7px; cursor: pointer; display: flex; align-items: center; justify-content: space-between; margin-bottom: 2px; }`n'
            . '        .select-option:hover { background-color: #E5E7DC !important; color: #000000; transform: translateX(3px); }`n'
            . '        .select-option.selected { background-color: #E2F6B8 !important; color: #2D4A0C; font-weight: 700; }`n'
            . '        .lime-card { background: #D8FA63; border-radius: 12px; padding: 9px 13px; margin-bottom: 12px; border: 1px solid #C4EC44; max-height: 70px; overflow-y: auto; }`n'
            . '        .lime-tag { font-size: 10.5px; font-weight: 800; letter-spacing: 0.8px; color: #4D7C0F; text-transform: uppercase; margin-bottom: 2px; }`n'
            . '        .lime-text { font-size: 12px; font-weight: 700; color: #141416; word-break: break-all; line-height: 1.35; }`n'
            . '        .btn-row { display: table; width: 100%; }`n'
            . '        .btn-cell { display: table-cell; width: 50%; padding-right: 6px; }`n'
            . '        .btn-cell:last-child { padding-right: 0; padding-left: 6px; }`n'
            . '        .btn { width: 100%; height: 42px; border-radius: 11px; font-size: 13.5px; font-weight: 800; cursor: pointer; border: none; text-align: center; }`n'
            . '        .btn-dark { background: #18181B; color: #FFFFFF; }`n'
            . '        .btn-dark:hover { background: #27272A; }`n'
            . '        .btn-lime { background: #D8FA63; color: #18181B; border: 1px solid #C4EC44; }`n'
            . '        .btn-lime:hover { background: #C8EA2D; }`n'
            . '        #centerModalToast { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); width: 270px; background: rgba(24, 24, 27, 0.82); -webkit-backdrop-filter: blur(16px); backdrop-filter: blur(16px); color: #FFFFFF; padding: 22px 18px; border-radius: 18px; text-align: center; display: none; z-index: 999999; box-shadow: 0 16px 40px rgba(0, 0, 0, 0.35); border: 1px solid rgba(255, 255, 255, 0.08); }`n'
            . '        .toast-icon { width: 38px; height: 38px; line-height: 38px; background: #D8FA63; color: #18181B; border-radius: 50%; font-size: 20px; font-weight: 900; margin: 0 auto 10px auto; }`n'
            . '        .toast-title { font-size: 14.5px; font-weight: 800; color: #FFFFFF; margin-bottom: 4px; }`n'
            . '        .toast-desc { font-size: 11.5px; color: rgba(255, 255, 255, 0.75); }`n'
            . '        .page-section { display: none; }`n'
            . '        .page-section.active { display: block; }`n'
            . '        .ver-bottom { display: flex; justify-content: center; margin-top: 10px; }`n'
            . '        .ver-pill { display: inline-block; background-color: #D8FA63; color: #18181B; font-size: 11.5px; font-weight: 800; padding: 3px 14px; border-radius: 6px; }`n'
            . "    </style>`n"
            . "</head>`n"
            . "<body>`n"
            . '    <div id="centerModalToast">`n'
            . '        <div class="toast-icon" id="toastIcon">✓</div>`n'
            . '        <div class="toast-title" id="toastTitle">配置保存成功</div>`n'
            . '        <div class="toast-desc" id="toastDesc">全部配置已生效，可直接开始翻译</div>`n'
            . "    </div>`n"
            . '    <div class="container">`n'
            . '        <div class="header-bar">`n'
            . '            <div class="brand-left">`n'
            . "                {{LOGO_ELEMENT}}`n"
            . '                <div class="brand-title">`n'
            . '                    <div class="brand-name">AI TRANSLATOR</div>`n'
            . '                    <div class="brand-sub">with Live Brain</div>`n'
            . "                </div>`n"
            . "            </div>`n"
            . '            <div class="pills-right">`n'
            . '                <div class="pill active" id="tabEngine" onclick="switchTab(\'engine\')">实时引擎</div>`n'
            . '                <div class="pill" id="tabHotkey" onclick="switchTab(\'hotkey\')">快捷键</div>`n'
            . "            </div>`n"
            . "        </div>`n"
            . '        <div class="page-section active" id="pageEngine">`n'
            . '            <div class="tag">LIVE INTELLIGENT TRANSLATION</div>`n'
            . '            <div class="main-title">打字翻译，在每一次思考后生成</div>`n'
            . '            <div class="sub-desc">连接大模型大脑，自动识别中外文并地道转化输出。</div>`n'
            . '            <div class="card" style="z-index: 50;">`n'
            . '                <div class="card-header">Language Preference · 语言设定</div>`n'
            . '                <div class="form-row" style="z-index: 52;">`n'
            . '                    <div class="form-label">源语言</div>`n'
            . '                    <div class="form-field">`n'
            . '                        <div class="custom-select" id="select-sourceLang" data-value="{{SOURCE_LANG_VAL}}">`n'
            . '                            <div class="select-trigger" onclick="toggleDropdown(\'select-sourceLang\')">`n'
            . '                                <span class="select-text">{{SOURCE_LANG_TEXT}}</span>`n'
            . '                                <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>`n'
            . "                            </div>`n"
            . '                            <div class="select-dropdown">`n'
            . '                                <div class="capsule-track"><div class="capsule-thumb" id="thumb-sourceLang"></div></div>`n'
            . '                                <div class="select-scroll-viewport" onscroll="updateScroll(\'select-sourceLang\', \'thumb-sourceLang\')">`n'
            . '                                    <div class="select-option" data-value="auto" onclick="selectOption(\'select-sourceLang\', \'auto\', \'自动识别 (中英双向智能互译)\')">自动识别 (中英双向智能互译)</div>`n'
            . '                                    <div class="select-option" data-value="zh" onclick="selectOption(\'select-sourceLang\', \'zh\', \'中文 (Chinese)\')">中文 (Chinese)</div>`n'
            . '                                    <div class="select-option" data-value="en" onclick="selectOption(\'select-sourceLang\', \'en\', \'English (英语)\')">English (英语)</div>`n'
            . '                                    <div class="select-option" data-value="ja" onclick="selectOption(\'select-sourceLang\', \'ja\', \'日本語 (Japanese)\')">日本語 (Japanese)</div>`n'
            . '                                    <div class="select-option" data-value="ko" onclick="selectOption(\'select-sourceLang\', \'ko\', \'한국어 (Korean)\')">한국어 (Korean)</div>`n'
            . '                                    <div class="select-option" data-value="pl" onclick="selectOption(\'select-sourceLang\', \'pl\', \'Polski (波兰语)\')">Polski (波兰语)</div>`n'
            . "                                </div>`n"
            . "                            </div>`n"
            . "                        </div>`n"
            . "                    </div>`n"
            . "                </div>`n"
            . '                <div class="form-row" style="z-index: 51;">`n'
            . '                    <div class="form-label">目标语言</div>`n'
            . '                    <div class="form-field">`n'
            . '                        <div class="custom-select" id="select-targetLang" data-value="{{TARGET_LANG_VAL}}">`n'
            . '                            <div class="select-trigger" onclick="toggleDropdown(\'select-targetLang\')">`n'
            . '                                <span class="select-text">{{TARGET_LANG_TEXT}}</span>`n'
            . '                                <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>`n'
            . "                            </div>`n"
            . '                            <div class="select-dropdown">`n'
            . '                                <div class="capsule-track"><div class="capsule-thumb" id="thumb-targetLang"></div></div>`n'
            . '                                <div class="select-scroll-viewport" onscroll="updateScroll(\'select-targetLang\', \'thumb-targetLang\')">`n'
            . '                                    <div class="select-option" data-value="en" onclick="selectOption(\'select-targetLang\', \'en\', \'English (英语)\')">English (英语)</div>`n'
            . '                                    <div class="select-option" data-value="zh" onclick="selectOption(\'select-targetLang\', \'zh\', \'中文 (Chinese)\')">中文 (Chinese)</div>`n'
            . '                                    <div class="select-option" data-value="pl" onclick="selectOption(\'select-targetLang\', \'pl\', \'Polski (波兰语)\')">Polski (波兰语)</div>`n'
            . '                                    <div class="select-option" data-value="ja" onclick="selectOption(\'select-targetLang\', \'ja\', \'日本語 (Japanese)\')">日本語 (Japanese)</div>`n'
            . '                                    <div class="select-option" data-value="ko" onclick="selectOption(\'select-targetLang\', \'ko\', \'한국어 (Korean)\')">한국어 (Korean)</div>`n'
            . '                                    <div class="select-option" data-value="es" onclick="selectOption(\'select-targetLang\', \'es\', \'Español (西班牙语)\')">Español (西班牙语)</div>`n'
            . '                                    <div class="select-option" data-value="fr" onclick="selectOption(\'select-targetLang\', \'fr\', \'Français (法语)\')">Français (法语)</div>`n'
            . '                                    <div class="select-option" data-value="de" onclick="selectOption(\'select-targetLang\', \'de\', \'Deutsch (德语)\')">Deutsch (德语)</div>`n'
            . '                                    <div class="select-option" data-value="ru" onclick="selectOption(\'select-targetLang\', \'ru\', \'Русский (俄语)\')">Русский (俄语)</div>`n'
            . "                                </div>`n"
            . "                            </div>`n"
            . "                        </div>`n"
            . "                    </div>`n"
            . "                </div>`n"
            . "            </div>`n"
            . '            <div class="card" style="z-index: 40;">`n'
            . '                <div class="card-header">AI Engine & Endpoint · 大模型配置</div>`n'
            . '                <div class="form-row" style="z-index: 41;">`n'
            . '                    <div class="form-label">AI 平台</div>`n'
            . '                    <div class="form-field">`n'
            . '                        <div class="custom-select" id="select-provider" data-value="{{PROVIDER_VAL}}">`n'
            . '                            <div class="select-trigger" onclick="toggleDropdown(\'select-provider\')">`n'
            . '                                <span class="select-text">{{PROVIDER_TEXT}}</span>`n'
            . '                                <svg class="select-arrow" viewBox="0 0 24 24"><polyline points="6 9 12 15 18 9"></polyline></svg>`n'
            . "                            </div>`n"
            . '                            <div class="select-dropdown" style="height: 180px;">`n'
            . '                                <div class="capsule-track"><div class="capsule-thumb" id="thumb-provider"></div></div>`n'
            . '                                <div class="select-scroll-viewport" onscroll="updateScroll(\'select-provider\', \'thumb-provider\')">`n'
            . '                                    <div class="select-option" data-value="Gemini" onclick="selectOption(\'select-provider\', \'Gemini\', \'Gemini (需魔法)\')">Gemini (需魔法)</div>`n'
            . '                                    <div class="select-option" data-value="OpenAI" onclick="selectOption(\'select-provider\', \'OpenAI\', \'ChatGPT (需魔法)\')">ChatGPT (需魔法)</div>`n'
            . '                                    <div class="select-option" data-value="NVIDIA" onclick="selectOption(\'select-provider\', \'NVIDIA\', \'NVIDIA·免费满血模型 (需魔法)\')">NVIDIA·免费满血模型 (需魔法)</div>`n'
            . '                                    <div class="select-option" data-value="DeepSeek" onclick="selectOption(\'select-provider\', \'DeepSeek\', \'DeepSeek (官方直连·深度思考)\')">DeepSeek (官方直连·深度思考)</div>`n'
            . '                                    <div class="select-option" data-value="Doubao" onclick="selectOption(\'select-provider\', \'Doubao\', \'豆包(ByteDance)\')">豆包(ByteDance)</div>`n'
            . '                                    <div class="select-option" data-value="Custom" onclick="selectOption(\'select-provider\', \'Custom\', \'自定义API(OpenAI 协议兼容)\')">自定义API(OpenAI 协议兼容)</div>`n'
            . "                                </div>`n"
            . "                            </div>`n"
            . "                        </div>`n"
            . "                    </div>`n"
            . "                </div>`n"
            . '                <div class="form-row">`n'
            . '                    <div class="form-label">Base URL</div>`n'
            . '                    <div class="form-field"><input type="text" id="baseUrl" class="input-box" value="{{BASE_URL}}" /></div>`n'
            . "                </div>`n"
            . '                <div class="form-row">`n'
            . '                    <div class="form-label">Model Name</div>`n'
            . '                    <div class="form-field"><input type="text" id="model" class="input-box" value="{{MODEL_NAME}}" /></div>`n'
            . "                </div>`n"
            . '                <div class="form-row">`n'
            . '                    <div class="form-label">API Key</div>`n'
            . '                    <div class="form-field"><input type="password" id="apiKey" class="input-box" value="{{API_KEY}}" /></div>`n'
            . "                </div>`n"
            . "            </div>`n"
            . '            <div class="lime-card">`n'
            . '                <div class="lime-tag">System Status · 状态反馈</div>`n'
            . '                <div class="lime-text" id="statusText">已切换至「{{PROVIDER_VAL}}」，专属配置已自动载入。</div>`n'
            . "            </div>`n"
            . '            <div class="btn-row">`n'
            . '                <div class="btn-cell"><button class="btn btn-dark" onclick="testApi()">🚀 检测 API 有效性</button></div>`n'
            . '                <div class="btn-cell"><button class="btn btn-lime" onclick="saveSettings()">💾 保存并生效</button></div>`n'
            . "            </div>`n"
            . '            <div class="ver-bottom"><div class="ver-pill">当前版本: v{{VER}}</div></div>`n'
            . "        </div>`n"
            . '        <div class="page-section" id="pageHotkey">`n'
            . '            <div class="tag">KEYBOARD SHORTCUTS</div>`n'
            . '            <div class="main-title">全域热键交互体系</div>`n'
            . '            <div class="sub-desc">在任意软件中随心唤醒实时翻译浮窗。</div>`n'
            . '            <div class="card">`n'
            . '                <div class="card-header">Global Triggers · 呼出热键</div>`n'
            . '                <div class="form-row"><div class="form-label">呼出输入条</div><div class="form-field"><input type="text" class="input-box" value="Alt + Y (!y)" readonly /></div></div>`n'
            . '                <div class="form-row"><div class="form-label">打开设置中心</div><div class="form-field"><input type="text" class="input-box" value="Alt + S (!s)" readonly /></div></div>`n'
            . "            </div>`n"
            . "        </div>`n"
            . "    </div>`n"
            . "    <script>`n"
            . "        function switchTab(tab) {`n"
            . '            document.getElementById("tabEngine").className = "pill" + (tab === "engine" ? " active" : "");`n'
            . '            document.getElementById("tabHotkey").className = "pill" + (tab === "hotkey" ? " active" : "");`n'
            . '            document.getElementById("pageEngine").className = "page-section" + (tab === "engine" ? " active" : "");`n'
            . '            document.getElementById("pageHotkey").className = "page-section" + (tab === "hotkey" ? " active" : "");`n'
            . "        }`n"
            . "        function toggleDropdown(id) {`n"
            . "            var el = document.getElementById(id);`n"
            . '            var wasOpen = el.classList.contains("open");`n'
            . "            closeAllDropdowns();`n"
            . '            if (!wasOpen) el.classList.add("open");`n'
            . "        }`n"
            . "        function closeAllDropdowns() {`n"
            . '            var drops = document.querySelectorAll(".custom-select");`n'
            . '            for (var i = 0; i < drops.length; i++) drops[i].classList.remove("open");`n'
            . "        }`n"
            . "        function selectOption(selectId, val, text) {`n"
            . "            var el = document.getElementById(selectId);`n"
            . '            el.setAttribute("data-value", val);`n'
            . '            el.querySelector(".select-text").innerText = text;`n'
            . '            var opts = el.querySelectorAll(".select-option");`n'
            . "            for (var i = 0; i < opts.length; i++) {`n"
            . '                if (opts[i].getAttribute("data-value") === val) opts[i].classList.add("selected");`n'
            . '                else opts[i].classList.remove("selected");`n'
            . "            }`n"
            . "            closeAllDropdowns();`n"
            . '            if (selectId === "select-provider") {`n'
            . '                var st = document.getElementById("statusText");`n'
            . '                if (st) st.innerText = "已切换至「" + val + "」，专属配置已自动载入。";`n'
            . "            }`n"
            . "        }`n"
            . "        function updateScroll(selectId, thumbId) {`n"
            . "            var el = document.getElementById(selectId);`n"
            . '            var view = el.querySelector(".select-scroll-viewport");`n'
            . "            var thumb = document.getElementById(thumbId);`n"
            . "            if (!view || !thumb) return;`n"
            . "            var maxScroll = view.scrollHeight - view.clientHeight;`n"
            . '            if (maxScroll <= 0) { thumb.style.height = "100%"; thumb.style.top = "0px"; return; }`n'
            . "            var maxTop = view.clientHeight - thumb.clientHeight - 8;`n"
            . "            var pct = view.scrollTop / maxScroll;`n"
            . '            thumb.style.top = (pct * maxTop) + "px";`n'
            . "        }`n"
            . '        document.onclick = function(e) { if (!e.target.closest(".custom-select")) closeAllDropdowns(); };`n'
            . "        function showToast(icon, title, desc) {`n"
            . '            var toast = document.getElementById("centerModalToast");`n'
            . '            document.getElementById("toastIcon").innerText = icon;`n'
            . '            document.getElementById("toastTitle").innerText = title;`n'
            . '            document.getElementById("toastDesc").innerText = desc;`n'
            . '            toast.style.display = "block";`n'
            . '            setTimeout(function() { toast.style.display = "none"; }, 1800);`n'
            . "        }`n"
            . "        function saveSettings() {`n"
            . "            window.ahkBridge.SaveSettings(`n"
            . '                document.getElementById("select-sourceLang").getAttribute("data-value"),`n'
            . '                document.getElementById("select-targetLang").getAttribute("data-value"),`n'
            . '                document.getElementById("select-provider").getAttribute("data-value"),`n'
            . '                document.getElementById("baseUrl").value,`n'
            . '                document.getElementById("model").value,`n'
            . '                document.getElementById("apiKey").value`n'
            . "            );`n"
            . "        }`n"
            . "        function testApi() {`n"
            . "            window.ahkBridge.TestApi(`n"
            . '                document.getElementById("select-provider").getAttribute("data-value"),`n'
            . '                document.getElementById("baseUrl").value,`n'
            . '                document.getElementById("model").value,`n'
            . '                document.getElementById("apiKey").value`n'
            . "            );`n"
            . "        }`n"
            . "    </script>`n"
            . "</body>`n"
            . "</html>"

        html := StrReplace(htmlTemplate, "{{LOGO_ELEMENT}}", logoElement)
        html := StrReplace(html, "{{SOURCE_LANG_VAL}}", sLang)
        html := StrReplace(html, "{{SOURCE_LANG_TEXT}}", sText)
        html := StrReplace(html, "{{TARGET_LANG_VAL}}", tLang)
        html := StrReplace(html, "{{TARGET_LANG_TEXT}}", tText)
        html := StrReplace(html, "{{PROVIDER_VAL}}", prov)
        html := StrReplace(html, "{{PROVIDER_TEXT}}", pText)
        html := StrReplace(html, "{{BASE_URL}}", bUrl)
        html := StrReplace(html, "{{MODEL_NAME}}", mdl)
        html := StrReplace(html, "{{API_KEY}}", key)
        html := StrReplace(html, "{{VER}}", ver)
        return html
    }
}