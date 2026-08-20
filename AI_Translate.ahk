#Requires AutoHotkey v2.0

class AITranslator {

    ; =========================================================================
    ; 统一请求入口 (智能推导引擎通道)
    ; =========================================================================
    static Request(text, cfg, targetLang := "en", sourceLang := "auto") {
        if (Trim(text) == "")
            return { success: false, msg: "输入内容为空", result: "" }

        provider := cfg.Has("provider") ? cfg["provider"] : ""
        baseUrl := cfg.Has("base_url") ? cfg["base_url"] : ""
        model := cfg.Has("model") ? cfg["model"] : ""

        if (provider == "") {
            if InStr(baseUrl, "googleapis.com") && !InStr(baseUrl, "openai")
                provider := "Gemini"
            else if InStr(baseUrl, "dashscope.aliyuncs.com")
                provider := "Qwen"
            else if InStr(baseUrl, "nvidia.com") || InStr(baseUrl, "meta")
                provider := "NVIDIA"
            else if InStr(baseUrl, "deepseek.com")
                provider := "DeepSeek"
            else if InStr(baseUrl, "volces.com")
                provider := "Doubao"
            else
                provider := "OpenAI"
        }

        if (provider == "Doubao" && (InStr(model, "translation") || InStr(model, "seed"))) {
            return this.RequestDoubaoTranslation(text, cfg, targetLang, sourceLang)
        }

        if (provider == "Gemini") {
            return this.RequestGemini(text, cfg, targetLang, sourceLang)
        }

        if (provider == "Meta") {
            if (!cfg.Has("base_url") || cfg["base_url"] == "")
                cfg["base_url"] := "https://integrate.api.nvidia.com/v1"
            return this.RequestOpenAICompatible(text, cfg, targetLang, sourceLang)
        }

        if (provider == "NVIDIA") {
            if (InStr(model, "riva"))
                return this.RequestNvidiaSpecial(text, cfg, targetLang, sourceLang)
            else
                return this.RequestOpenAICompatible(text, cfg, targetLang, sourceLang)
        }

        return this.RequestOpenAICompatible(text, cfg, targetLang, sourceLang)
    }

    ; =========================================================================
    ; 0. 火山方舟 Doubao-Seed-Translation 专用翻译接口实现
    ; =========================================================================
    static RequestDoubaoTranslation(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 API Key", result: "" }

        url := "https://ark.cn-beijing.volces.com/api/v3/responses"
        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : ""
        
        sLang := (sourceLang == "" || sourceLang == "auto") ? "zh" : sourceLang
        tLang := (targetLang == "" ) ? "en" : targetLang

        payload := '{"model":' . this.EscapeJSON(model) 
            . ',"input":[{"role":"user","content":[{"type":"input_text","text":' . this.EscapeJSON(text) 
            . ',"translation_options":{"source_language":' . this.EscapeJSON(sLang) . ',"target_language":' . this.EscapeJSON(tLang) . "}}}]}]}"

        headers := Map(
            "Content-Type", "application/json; charset=utf-8",
            "Authorization", "Bearer " . apiKey
        )

        return this.ExecuteWinHttp(url, "POST", payload, headers, cfg)
    }

    ; =========================================================================
    ; 专属定制：NVIDIA 旧版 Riva 翻译模型的特供保底通道
    ; =========================================================================
    static RequestNvidiaSpecial(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 API Key", result: "" }

        baseUrl := cfg.Has("base_url") ? RTrim(cfg["base_url"], "/") : "https://integrate.api.nvidia.com/v1"
        url := baseUrl . "/chat/completions"
        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : "nvidia/riva-translate-4b-instruct-v2"

        tName := this.GetLangFullName(targetLang)
        sysPrompt := "Translate the user text into " . tName . ". Output only the translation."

        payload := '{"model":' . this.EscapeJSON(model) 
            . ',"messages":['
            . '{"role":"system","content":' . this.EscapeJSON(sysPrompt) . '},'
            . '{"role":"user","content":' . this.EscapeJSON(text) . '}'
            . '],"temperature":0.0,"max_tokens":1024}'

        headers := Map(
            "Content-Type", "application/json; charset=utf-8",
            "Authorization", "Bearer " . apiKey
        )

        return this.ExecuteWinHttp(url, "POST", payload, headers, cfg)
    }

    ; =========================================================================
    ; 1. Google Gemini 接口实现 (双向互译自适应)
    ; =========================================================================
    static RequestGemini(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 Gemini API Key", result: "" }

        baseUrl := cfg.Has("base_url") ? RTrim(cfg["base_url"], "/") : "https://generativelanguage.googleapis.com/v1beta"
        if (!InStr(baseUrl, "v1beta") && !InStr(baseUrl, "v1"))
            baseUrl .= "/v1beta"

        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : "gemini-flash-latest"
        url := baseUrl . "/models/" . model . ":generateContent?key=" . apiKey

        prompt := this.GetBilingualSmartPrompt(text, targetLang, sourceLang)

        payload := '{"contents":[{"parts":[{"text":' . this.EscapeJSON(prompt) . '}]}]}'

        return this.ExecuteWinHttp(url, "POST", payload, Map("Content-Type", "application/json; charset=utf-8"), cfg)
    }

    ; =========================================================================
    ; 2. OpenAI 兼容协议实现 (适用于 DeepSeek, Qwen 等顶级大模型)
    ; =========================================================================
    static RequestOpenAICompatible(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 API Key", result: "" }

        baseUrl := cfg.Has("base_url") ? RTrim(cfg["base_url"], "/") : ""
        if (baseUrl == "")
            baseUrl := "https://api.openai.com/v1"
        
        url := baseUrl
        if (!InStr(url, "/chat/completions"))
            url .= "/chat/completions"

        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : "deepseek-chat"

        sysPrompt := this.GetBilingualSystemPrompt(targetLang, sourceLang)

        payload := '{"model":' . this.EscapeJSON(model) 
            . ',"messages":['
            . '{"role":"system","content":' . this.EscapeJSON(sysPrompt) . '},'
            . '{"role":"user","content":' . this.EscapeJSON(text) . '}'
            . '],"temperature":0.1,"max_tokens":2048}'

        headers := Map(
            "Content-Type", "application/json; charset=utf-8",
            "Authorization", "Bearer " . apiKey
        )

        return this.ExecuteWinHttp(url, "POST", payload, headers, cfg)
    }

    ; =========================================================================
    ; 💡 升级版：真·中英双向智能互译系统提示词
    ; =========================================================================
    static GetBilingualSystemPrompt(targetLang, sourceLang) {
        if (sourceLang == "" || sourceLang == "auto") {
            ; 当设置为自动识别时，启用真·双向互译逻辑（中文转英文，英文转简体中文）
            return "You are a professional bidirectional translation engine between Chinese and English. Automatically detect the language of the input text: if the input text is Chinese, translate it fluently into natural English; if the input text is English, translate it fluently into natural Simplified Chinese. Output ONLY the translated text without any explanation, notes, or quotes."
        }

        sName := this.GetLangFullName(sourceLang)
        tName := this.GetLangFullName(targetLang)

        return "You are a bilingual translation engine between " . sName . " and " . tName . ". "
            . "Analyze the input text: if it is in " . sName . ", translate it accurately into " . tName . "; "
            . "if it is in " . tName . ", translate it accurately into " . sName . ". "
            . "Output ONLY the translated text without any explanation or notes."
    }

    static GetBilingualSmartPrompt(text, targetLang, sourceLang) {
        sys := this.GetBilingualSystemPrompt(targetLang, sourceLang)
        return sys . "`n`nText to translate:`n" . text
    }

    ; =========================================================================
    ; 获取语言标准名称
    ; =========================================================================
    static GetLangFullName(code) {
        static langMap := Map(
            "zh", "Simplified Chinese",
            "en", "English",
            "ja", "Japanese",
            "ko", "Korean",
            "es", "Spanish",
            "fr", "French",
            "de", "German",
            "ru", "Russian"
        )
        return langMap.Has(code) ? langMap[code] : code
    }

    ; =========================================================================
    ; 底层 WinHttp 请求驱动
    ; =========================================================================
    static ExecuteWinHttp(url, method, payload, headers, cfg) {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open(method, url, true)

            proxyEnabled := cfg.Has("proxy_enabled") ? cfg["proxy_enabled"] : false
            proxyHost := cfg.Has("proxy_host") ? cfg["proxy_host"] : "127.0.0.1"
            proxyPort := cfg.Has("proxy_port") ? cfg["proxy_port"] : 7890

            if (proxyEnabled) {
                http.SetProxy(2, proxyHost . ":" . proxyPort)
            }

            http.SetTimeouts(5000, 5000, 15000, 45000)

            for hKey, hVal in headers {
                http.SetRequestHeader(hKey, hVal)
            }

            http.Send(payload)
            
            if (!http.WaitForResponse(45)) {
                return { success: false, msg: "网络请求超时 (服务器响应过慢)", result: "" }
            }

            status := http.Status

            oStream := ComObject("ADODB.Stream")
            oStream.Type := 1
            oStream.Open()
            oStream.Write(http.ResponseBody)
            oStream.Position := 0
            oStream.Type := 2
            oStream.Charset := "utf-8"
            resp := oStream.ReadText()
            oStream.Close()

            if (status != 200) {
                errDetail := this.ExtractErrorMessage(resp)
                return { success: false, msg: "HTTP " . status . (errDetail != "" ? ": " . errDetail : ""), result: "" }
            }

            parsedText := this.ExtractedContent(resp)
            if (parsedText != "") {
                return { success: true, msg: "OK", result: parsedText }
            } else {
                return { success: false, msg: "未能解析翻译结果返回", result: "" }
            }
        } catch as err {
            return { success: false, msg: "网络请求异常: " . err.Message, result: "" }
        }
    }

    static MapToJSON(obj) {
        if !IsObject(obj) {
            if IsNumber(obj)
                return String(obj)
            if (obj == true)
                return "true"
            if (obj == false)
                return "false"
            return this.EscapeJSON(String(obj))
        }

        if (obj is Array) {
            items := []
            for val in obj {
                items.Push(this.MapToJSON(val))
            }
            res := "["
            for i, item in items {
                res .= (i == 1 ? "" : ",") . item
            }
            return res . "]"
        }

        if (obj is Map) {
            items := []
            for k, v in obj {
                items.Push(this.EscapeJSON(String(k)) . ":" . this.MapToJSON(v))
            }
            res := "{"
            for i, item in items {
                res .= (i == 1 ? "" : ",") . item
            }
            return res . "}"
        }

        items := []
        for k, v in obj.OwnProps() {
            items.Push(this.EscapeJSON(String(k)) . ":" . this.MapToJSON(v))
        }
        res := "{"
        for i, item in items {
            res .= (i == 1 ? "" : ",") . item
        }
        return res . "}"
    }

    static ExtractedContent(jsonStr) {
        if RegExMatch(jsonStr, '\"text\"\s*:\s*\"((?:\\.|[^\"])*)\"', &m)
            return this.UnescapeJSON(m[1])

        if RegExMatch(jsonStr, '\"content\"\s*:\s*\"((?:\\.|[^\"])*)\"', &m)
            return this.UnescapeJSON(m[1])

        return ""
    }

    static ExtractErrorMessage(jsonStr) {
        if RegExMatch(jsonStr, '\"message\"\s*:\s*\"((?:\\.|[^\"])*)\"', &m)
            return this.UnescapeJSON(m[1])
        return ""
    }

    static EscapeJSON(str) {
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, '"', '\"')
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return '"' . str . '"'
    }

    static UnescapeJSON(str) {
        str := StrReplace(str, '\"', '"')
        str := StrReplace(str, "\n", "`n")
        str := StrReplace(str, "\r", "`r")
        str := StrReplace(str, "\t", "`t")
        str := StrReplace(str, "\\", "\")
        return Trim(str, " `t`r`n`"")
    }
}