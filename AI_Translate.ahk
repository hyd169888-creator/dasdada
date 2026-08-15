#Requires AutoHotkey v2.0

class AITranslator {

    ; =========================================================================
    ; 统一请求入口
    ; =========================================================================
    static Request(text, cfg, targetLang := "en", sourceLang := "auto") {
        if (Trim(text) == "")
            return { success: false, msg: "输入内容为空", result: "" }

        provider := cfg.Has("provider") ? cfg["provider"] : "Gemini"

        ; 1. Google Gemini 专用通道
        if (provider == "Gemini") {
            return this.RequestGemini(text, cfg, targetLang, sourceLang)
        }

        ; 2. 通义千问 (Qwen) 默认通道
        if (provider == "Qwen") {
            if (!cfg.Has("base_url") || cfg["base_url"] == "")
                cfg["base_url"] := "https://dashscope.aliyuncs.com/compatible-mode/v1"
            if (!cfg.Has("model") || cfg["model"] == "")
                cfg["model"] := "qwen-plus"
            return this.RequestOpenAICompatible(text, cfg, targetLang, sourceLang)
        }

        ; 3. 标准 OpenAI 兼容协议（DeepSeek, OpenAI, NVIDIA, Doubao, Custom）
        if (provider == "OpenAI" || provider == "DeepSeek" || provider == "NVIDIA" || provider == "Doubao" || provider == "Custom") {
            return this.RequestOpenAICompatible(text, cfg, targetLang, sourceLang)
        }

        return { success: false, msg: "未知的翻译模型引擎: " . provider, result: "" }
    }

    ; =========================================================================
    ; 1. Google Gemini 接口实现
    ; =========================================================================
    static RequestGemini(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 Gemini API Key", result: "" }

        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : "gemini-flash-latest"
        url := "https://generativelanguage.googleapis.com/v1beta/models/" . model . ":generateContent?key=" . apiKey

        targetName := this.GetLangName(targetLang)
        prompt := "Translate the following text into " . targetName . ". Only return the direct translation without any explanation, markdown formatting, or introductory words:`n`n" . text

        payload := '{"contents":[{"parts":[{"text":' . this.EscapeJSON(prompt) . '}]}]}'

        return this.ExecuteWinHttp(url, "POST", payload, Map("Content-Type", "application/json"), cfg)
    }

    ; =========================================================================
    ; 2. OpenAI 兼容协议实现 (Qwen / DeepSeek / OpenAI / NVIDIA / Doubao)
    ; =========================================================================
    static RequestOpenAICompatible(text, cfg, targetLang, sourceLang) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        if (apiKey == "")
            return { success: false, msg: "未配置 API Key", result: "" }

        baseUrl := cfg.Has("base_url") ? RTrim(cfg["base_url"], "/") : ""
        if (baseUrl == "")
            baseUrl := "https://api.openai.com/v1"
        
        url := baseUrl . "/chat/completions"
        model := (cfg.Has("model") && cfg["model"] != "") ? cfg["model"] : "gpt-3.5-turbo"

        targetName := this.GetLangName(targetLang)
        sysPrompt := "You are a professional translator. Translate the text into " . targetName . ". Output only the final translation directly without quotes, markdown, or extra explanations."

        payload := '{"model":' . this.EscapeJSON(model) 
            . ',"messages":['
            . '{"role":"system","content":' . this.EscapeJSON(sysPrompt) . '},'
            . '{"role":"user","content":' . this.EscapeJSON(text) . '}'
            . '],"temperature":0.3}'

        headers := Map(
            "Content-Type", "application/json",
            "Authorization", "Bearer " . apiKey
        )

        return this.ExecuteWinHttp(url, "POST", payload, headers, cfg)
    }

    ; =========================================================================
    ; 底层 WinHttp 请求驱动 (支持代理)
    ; =========================================================================
    static ExecuteWinHttp(url, method, payload, headers, cfg) {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open(method, url, true)

            ; 代理配置检查
            proxyEnabled := cfg.Has("proxy_enabled") ? cfg["proxy_enabled"] : false
            proxyHost := cfg.Has("proxy_host") ? cfg["proxy_host"] : "127.0.0.1"
            proxyPort := cfg.Has("proxy_port") ? cfg["proxy_port"] : 7890

            if (proxyEnabled) {
                http.SetProxy(2, proxyHost . ":" . proxyPort)
            }

            http.SetTimeouts(3000, 3000, 8000, 10000)

            for hKey, hVal in headers {
                http.SetRequestHeader(hKey, hVal)
            }

            http.Send(payload)
            http.WaitForResponse(10)

            status := http.Status
            resp := http.ResponseText

            if (status != 200) {
                errDetail := this.ExtractErrorMessage(resp)
                return { success: false, msg: "HTTP " . status . (errDetail != "" ? ": " . errDetail : ""), result: "" }
            }

            parsedText := this.ExtractContent(resp)
            if (parsedText != "") {
                return { success: true, msg: "OK", result: parsedText }
            } else {
                return { success: false, msg: "未能解析翻译结果返回", result: "" }
            }
        } catch as err {
            return { success: false, msg: "网络请求异常: " . err.Message, result: "" }
        }
    }

    ; =========================================================================
    ; JSON 序列化与解析辅助工具 (供 Settings_UI 调用)
    ; =========================================================================
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

        ; 普通 Object
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

    static ExtractContent(jsonStr) {
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

    static GetLangName(code) {
        static langMap := Map(
            "auto", "Auto Detection",
            "zh", "Simplified Chinese",
            "en", "English",
            "ja", "Japanese",
            "ko", "Korean",
            "es", "Spanish",
            "fr", "French",
            "de", "German",
            "ru", "Russian"
        )
        return langMap.Has(code) ? langMap[code] : "English"
    }
}