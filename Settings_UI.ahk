#Requires AutoHotkey v2.0

class SettingsUI {
    static configFile := A_ScriptDir . "\config.json"
    static gui := 0
    static wv := 0
    static onHotkeysUpdatedCallback := 0

    ; 默认配置
    static defaultConfig := Map(
        "source_lang", "auto",
        "target_lang", "en",
        "provider", "nvidia",
        "base_url", "https://integrate.api.nvidia.com/v1",
        "model", "meta/llama-3.1-8b-instruct",
        "api_key", "",
        "hotkeys", Map(
            "show_bar", "!y",
            "settings", "!s"
        )
    )

    ; 读取配置
    static LoadConfig() {
        if !FileExist(this.configFile) {
            this.SaveConfig(this.defaultConfig)
            return this.defaultConfig
        }

        try {
            content := FileRead(this.configFile, "UTF-8")
            if (Trim(content) == "")
                return this.defaultConfig
            
            parsed := this._ParseJsonToMap(content)
            return parsed
        } catch {
            return this.defaultConfig
        }
    }

    ; 保存配置
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

    ; 显示设置中心
    static Show() {
        if (this.gui && WinExist("ahk_id " . this.gui.Hwnd)) {
            this.gui.Show()
            WinActivate("ahk_id " . this.gui.Hwnd)
            return
        }

        g := Gui("+Resize +MinSize520x680", "AI 智能打字翻译 - 设置中心")
        g.BackColor := "0xF8FAF5"
        g.MarginX := 0
        g.MarginY := 0
        this.gui := g

        wbCtl := g.Add("ActiveX", "w550 h720", "Shell.Explorer")
        this.wv := wbCtl.Value
        this.wv.silent := true
        this.wv.Navigate("about:blank")
        while (this.wv.ReadyState != 4)
            Sleep(10)

        cfg := this.LoadConfig()
        localVer := FileExist(A_ScriptDir . "\version.txt") ? Trim(FileRead(A_ScriptDir . "\version.txt", "UTF-8")) : "2.0.6"

        html := this._BuildHtml(cfg, localVer)
        doc := this.wv.Document
        doc.open()
        doc.write(html)
        doc.close()

        ; 注册 Web 交互桥接
        bridge := {
            SaveSettings: (sourceLang, targetLang, provider, baseUrl, model, apiKey) => SettingsUI._OnSaveSettings(sourceLang, targetLang, provider, baseUrl, model, apiKey),
            TestApi: (provider, baseUrl, model, apiKey) => SettingsUI._OnTestApi(provider, baseUrl, model, apiKey)
        }
        doc.parentWindow.ahkBridge := bridge

        g.OnEvent("Close", (*) => g.Hide())
        g.Show("w550 h720 Center")
    }

    static _OnSaveSettings(sourceLang, targetLang, provider, baseUrl, model, apiKey) {
        cfg := this.LoadConfig()
        cfg["source_lang"] := sourceLang
        cfg["target_lang"] := targetLang
        cfg["provider"] := provider
        cfg["base_url"] := baseUrl
        cfg["model"] := model
        cfg["api_key"] := apiKey

        if this.SaveConfig(cfg) {
            MsgBox("设置已成功保存并立即生效！", "保存成功", "Iconi")
        } else {
            MsgBox("配置文件写入失败，请检查文件写入权限。", "保存失败", "Iconx")
        }
    }

    static _OnTestApi(provider, baseUrl, model, apiKey) {
        if (apiKey == "") {
            MsgBox("请先输入 API Key 再进行测试！", "提示", "Icon!")
            return
        }

        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(5000, 5000, 10000, 10000)
            req.Open("POST", baseUrl . "/chat/completions", false)
            req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
            req.SetRequestHeader("Authorization", "Bearer " . apiKey)
            
            body := '{"model":"' . model . '","messages":[{"role":"user","content":"Hi"}],"max_tokens":5}'
            req.Send(body)

            if (req.Status == 200) {
                MsgBox("🎉 API 探测成功！模型响应正常，网络通道通畅。", "连接成功", "Iconi")
            } else {
                MsgBox("❌ 连接失败！HTTP 状态码: " . req.Status . "`n返回内容: " . req.ResponseText, "连接失败", "Iconx")
            }
        } catch as e {
            MsgBox("❌ 无法连接到指定服务端点，请检查网络/魔法或 Base URL 是否正确。`n错误详情: " . e.Message, "连接异常", "Iconx")
        }
    }

    static _BuildHtml(cfg, ver) {
        sLang := cfg.Has("source_lang") ? cfg["source_lang"] : "auto"
        tLang := cfg.Has("target_lang") ? cfg["target_lang"] : "en"
        prov := cfg.Has("provider") ? cfg["provider"] : "nvidia"
        bUrl := cfg.Has("base_url") ? cfg["base_url"] : "https://integrate.api.nvidia.com/v1"
        mdl := cfg.Has("model") ? cfg["model"] : "meta/llama-3.1-8b-instruct"
        key := cfg.Has("api_key") ? cfg["api_key"] : ""

        optSLangAuto := (sLang == "auto") ? "selected" : ""
        optSLangZh := (sLang == "zh") ? "selected" : ""
        optSLangEn := (sLang == "en") ? "selected" : ""

        optTLangEn := (tLang == "en") ? "selected" : ""
        optTLangZh := (tLang == "zh") ? "selected" : ""
        optTLangPl := (tLang == "pl") ? "selected" : ""
        optTLangJa := (tLang == "ja") ? "selected" : ""
        optTLangKo := (tLang == "ko") ? "selected" : ""

        htmlTemplate := "
        (
        <!DOCTYPE html>
        <html>
        <head>
        <meta http-equiv='X-UA-Compatible' content='IE=edge'>
        <meta charset='utf-8'>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, 'Microsoft YaHei UI', sans-serif; }
            body { background: #F8FAF5; padding: 24px; color: #18181B; }
            .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; }
            .logo-title { font-size: 20px; font-weight: 900; color: #0F172A; }
            .badge-bar { display: flex; gap: 8px; }
            .badge-btn { background: #18181B; color: #FFF; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 700; }
            .sub-title { font-size: 18px; font-weight: 800; color: #1E293B; margin-bottom: 4px; }
            .sub-desc { font-size: 12px; color: #64748B; margin-bottom: 20px; }
            .card { background: #FFF; border: 1.5px solid #E2E8F0; border-radius: 12px; padding: 16px; margin-bottom: 16px; }
            .card-title { font-size: 11px; font-weight: 800; color: #475569; letter-spacing: 0.5px; margin-bottom: 12px; }
            .field-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px; }
            .field-row:last-child { margin-bottom: 0; }
            .field-label { font-size: 13px; font-weight: 700; color: #334155; }
            select, input { width: 340px; height: 36px; border: 1.5px solid #E2E8F0; border-radius: 8px; padding: 0 10px; font-size: 13px; color: #0F172A; outline: none; }
            select:focus, input:focus { border-color: #84CC16; }
            .status-card { background: #D8FA63; border-radius: 10px; padding: 12px 16px; margin-bottom: 16px; }
            .status-title { font-size: 11px; font-weight: 800; color: #18181B; }
            .status-desc { font-size: 12px; font-weight: 700; color: #18181B; margin-top: 4px; }
            .btn-group { display: flex; gap: 12px; }
            .btn-test { flex: 1; height: 42px; background: #18181B; color: #FFF; border: none; border-radius: 10px; font-size: 13px; font-weight: 800; cursor: pointer; }
            .btn-save { flex: 1; height: 42px; background: #D8FA63; color: #18181B; border: 1px solid #C4E840; border-radius: 10px; font-size: 13px; font-weight: 800; cursor: pointer; box-shadow: 0 4px 12px rgba(216, 250, 99, 0.35); }
            .ver-bottom { display: flex; justify-content: center; margin-top: 18px; }
            .ver-badge { background: #D8FA63; color: #18181B; padding: 3px 12px; border-radius: 6px; font-size: 11px; font-weight: 800; }
        </style>
        </head>
        <body>
            <div class='header'>
                <div class='logo-title'>🔤 AI TRANSLATOR <span style='font-size:12px;font-weight:normal;color:#64748B;'>with Live Brain</span></div>
                <div class='badge-bar'>
                    <div class='badge-btn'>实时引擎</div>
                    <div class='badge-btn' style='background:#F1F5F9;color:#475569;'>快捷键</div>
                </div>
            </div>

            <div class='sub-title'>打字翻译，在每一次思考后生成</div>
            <div class='sub-desc'>连接大模型大脑，自动识别中外文并地道转化输出。</div>

            <div class='card'>
                <div class='card-title'>LANGUAGE PREFERENCE · 语言设定</div>
                <div class='field-row'>
                    <span class='field-label'>源语言</span>
                    <select id='sourceLang'>
                        <option value='auto' {{OPT_S_AUTO}}>自动识别 (中英双向智能互译)</option>
                        <option value='zh' {{OPT_S_ZH}}>Chinese (中文)</option>
                        <option value='en' {{OPT_S_EN}}>English (英语)</option>
                    </select>
                </div>
                <div class='field-row'>
                    <span class='field-label'>目标语言</span>
                    <select id='targetLang'>
                        <option value='en' {{OPT_T_EN}}>English (英语)</option>
                        <option value='zh' {{OPT_T_ZH}}>Chinese (中文)</option>
                        <option value='pl' {{OPT_T_PL}}>Polish (波兰语)</option>
                        <option value='ja' {{OPT_T_JA}}>Japanese (日语)</option>
                        <option value='ko' {{OPT_T_KO}}>Korean (韩语)</option>
                    </select>
                </div>
            </div>

            <div class='card'>
                <div class='card-title'>AI ENGINE & ENDPOINT · 大模型配置</div>
                <div class='field-row'>
                    <span class='field-label'>AI 平台</span>
                    <select id='provider'>
                        <option value='nvidia' selected>NVIDIA·免费满血模型 (需魔法)</option>
                        <option value='custom'>自定义 OpenAI 兼容端点</option>
                    </select>
                </div>
                <div class='field-row'>
                    <span class='field-label'>Base URL</span>
                    <input type='text' id='baseUrl' value='{{BASE_URL}}'>
                </div>
                <div class='field-row'>
                    <span class='field-label'>Model Name</span>
                    <input type='text' id='model' value='{{MODEL_NAME}}'>
                </div>
                <div class='field-row'>
                    <span class='field-label'>API Key</span>
                    <input type='password' id='apiKey' value='{{API_KEY}}'>
                </div>
            </div>

            <div class='status-card'>
                <div class='status-title'>SYSTEM STATUS · 状态反馈</div>
                <div class='status-desc'>💡 准备就绪，可点击下方按钮发起连通性探针测试。</div>
            </div>

            <div class='btn-group'>
                <button class='btn-test' onclick='testApi()'>🚀 检测 API 有效性</button>
                <button class='btn-save' onclick='saveSettings()'>💾 保存并生效</button>
            </div>

            <div class='ver-bottom'>
                <div class='ver-badge'>当前版本: v{{VER}}</div>
            </div>

            <script>
                function saveSettings() {
                    var sLang = document.getElementById('sourceLang').value;
                    var tLang = document.getElementById('targetLang').value;
                    var prov = document.getElementById('provider').value;
                    var bUrl = document.getElementById('baseUrl').value;
                    var mdl = document.getElementById('model').value;
                    var key = document.getElementById('apiKey').value;
                    window.ahkBridge.SaveSettings(sLang, tLang, prov, bUrl, mdl, key);
                }
                function testApi() {
                    var prov = document.getElementById('provider').value;
                    var bUrl = document.getElementById('baseUrl').value;
                    var mdl = document.getElementById('model').value;
                    var key = document.getElementById('apiKey').value;
                    window.ahkBridge.TestApi(prov, bUrl, mdl, key);
                }
            </script>
        </body>
        </html>
        )"

        html := StrReplace(htmlTemplate, "{{BASE_URL}}", bUrl)
        html := StrReplace(html, "{{MODEL_NAME}}", mdl)
        html := StrReplace(html, "{{API_KEY}}", key)
        html := StrReplace(html, "{{VER}}", ver)
        html := StrReplace(html, "{{OPT_S_AUTO}}", optSLangAuto)
        html := StrReplace(html, "{{OPT_S_ZH}}", optSLangZh)
        html := StrReplace(html, "{{OPT_S_EN}}", optSLangEn)
        html := StrReplace(html, "{{OPT_T_EN}}", optTLangEn)
        html := StrReplace(html, "{{OPT_T_ZH}}", optTLangZh)
        html := StrReplace(html, "{{OPT_T_PL}}", optTLangPl)
        html := StrReplace(html, "{{OPT_T_JA}}", optTLangJa)
        html := StrReplace(html, "{{OPT_T_KO}}", optTLangKo)
        return html
    }

    ; JSON 解析转 Map
    static _ParseJsonToMap(jsonStr) {
        cfg := Map(
            "source_lang", RegExMatch(jsonStr, '"source_lang"\s*:\s*"([^"]+)"', &m1) ? m1[1] : "auto",
            "target_lang", RegExMatch(jsonStr, '"target_lang"\s*:\s*"([^"]+)"', &m2) ? m2[1] : "en",
            "provider", RegExMatch(jsonStr, '"provider"\s*:\s*"([^"]+)"', &m3) ? m3[1] : "nvidia",
            "base_url", RegExMatch(jsonStr, '"base_url"\s*:\s*"([^"]+)"', &m4) ? m4[1] : "https://integrate.api.nvidia.com/v1",
            "model", RegExMatch(jsonStr, '"model"\s*:\s*"([^"]+)"', &m5) ? m5[1] : "meta/llama-3.1-8b-instruct",
            "api_key", RegExMatch(jsonStr, '"api_key"\s*:\s*"([^"]*)"', &m6) ? m6[1] : "",
            "hotkeys", Map(
                "show_bar", RegExMatch(jsonStr, '"show_bar"\s*:\s*"([^"]+)"', &h1) ? h1[1] : "!y",
                "settings", RegExMatch(jsonStr, '"settings"\s*:\s*"([^"]+)"', &h2) ? h2[1] : "!s"
            )
        )
        return cfg
    }

    ; Map 转 JSON
    static _MapToJson(cfg) {
        hk := cfg.Has("hotkeys") ? cfg["hotkeys"] : Map("show_bar", "!y", "settings", "!s")
        hBar := hk.Has("show_bar") ? hk["show_bar"] : "!y"
        hSet := hk.Has("settings") ? hk["settings"] : "!s"

        return '{`n'
            . '  "source_lang": "' . cfg["source_lang"] . '",`n'
            . '  "target_lang": "' . cfg["target_lang"] . '",`n'
            . '  "provider": "' . cfg["provider"] . '",`n'
            . '  "base_url": "' . cfg["base_url"] . '",`n'
            . '  "model": "' . cfg["model"] . '",`n'
            . '  "api_key": "' . cfg["api_key"] . '",`n'
            . '  "hotkeys": {`n'
            . '    "show_bar": "' . hBar . '",`n'
            . '    "settings": "' . hSet . '"`n'
            . '  }`n'
            . '}'
    }
}