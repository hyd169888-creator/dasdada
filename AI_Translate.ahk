#Requires AutoHotkey v2.0

class AITranslator {
    static langMap := Map(
        "auto", "Automatic Language Detection (translate Chinese to English, and English/others to fluent idiomatic Chinese)",
        "zh", "Simplified Chinese",
        "en", "Natural idiomatic American English",
        "ja", "Japanese",
        "ko", "Korean",
        "es", "Spanish",
        "fr", "French",
        "de", "German",
        "ru", "Russian",
        "pl", "Polish"
    )

    ; 兼容 Float_Bar 调用的 Request 接口
    static Request(text, providerCfg := 0, targetLang := "en", sourceLang := "auto") {
        if (providerCfg is String && (targetLang is Map || targetLang is Object)) {
            temp := providerCfg
            providerCfg := targetLang
            targetLang := temp
        }
        return this.Translate(text, targetLang, sourceLang, providerCfg)
    }

    static Translate(text, targetLang := "en", sourceLang := "auto", providerCfg := 0, isSecondRound := false) {
        if (Trim(text) == "")
            return ""

        if (!providerCfg || !IsObject(providerCfg)) {
            settingsFile := A_ScriptDir . "\config\setting.json"
            if FileExist(settingsFile) {
                try {
                    rawJson := FileRead(settingsFile, "UTF-8")
                    currProv := RegExMatch(rawJson, '"current_provider"\s*:\s*"([^"]+)"', &m) ? m[1] : "DeepSeek"
                    tLang := RegExMatch(rawJson, '"target_lang"\s*:\s*"([^"]+)"', &m) ? m[1] : "en"
                    sLang := RegExMatch(rawJson, '"source_lang"\s*:\s*"([^"]+)"', &m) ? m[1] : "auto"
                    
                    if (targetLang == "en" && tLang != "")
                        targetLang := tLang
                    if (sourceLang == "auto" && sLang != "")
                        sourceLang := sLang

                    if RegExMatch(rawJson, 's)"' . currProv . '"\s*:\s*\{([^}]*)\}', &pBlock) {
                        bStr := pBlock[1]
                        bUrl := RegExMatch(bStr, '"base_url"\s*:\s*"([^"]*)"', &u) ? u[1] : ""
                        bModel := RegExMatch(bStr, '"model"\s*:\s*"([^"]*)"', &md) ? md[1] : ""
                        bKey := RegExMatch(bStr, '"api_key"\s*:\s*"([^"]*)"', &k) ? k[1] : ""
                        providerCfg := Map("base_url", bUrl, "model", bModel, "api_key", bKey)
                    }
                }
            }
        }

        if (!providerCfg || !providerCfg.Has("api_key") || providerCfg["api_key"] == "") {
            return "【错误: 未配置有效的 API Key，请在设置中心填入并保存】"
        }

        apiKey := providerCfg["api_key"]
        baseUrl := RTrim(providerCfg["base_url"], "/")
        model := providerCfg["model"]

        targetPrompt := this.langMap.Has(targetLang) ? this.langMap[targetLang] : targetLang
        sourcePrompt := this.langMap.Has(sourceLang) ? this.langMap[sourceLang] : sourceLang

        systemPrompt := "You are a professional, high-accuracy native translator. "
            . "Translate the following user input directly into " . targetPrompt . ". "
            . "Original language setting: " . sourcePrompt . ". "
            . "CRITICAL INSTRUCTIONS: "
            . "1. Provide ONLY the pure translated output. "
            . "2. DO NOT include explanations, markdown formatting, greetings, notes, quotes, or thoughts. "
            . "3. Translate idioms and expressions into natural native equivalents."

        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(5000, 5000, 15000, 15000)

            cleanUrl := baseUrl
            if InStr(cleanUrl, "generativelanguage.googleapis.com") && !InStr(cleanUrl, "openai") {
                if (!InStr(cleanUrl, "v1beta") && !InStr(cleanUrl, "v1"))
                    cleanUrl .= "/v1beta"
                fullUrl := cleanUrl . "/models/" . model . ":generateContent?key=" . apiKey

                bodyObj := '{"contents":[{"parts":[{"text":' . this.EscapeJSON(systemPrompt . "`n`nText to translate:`n" . text) . '}]}]}'
                req.Open("POST", fullUrl, false)
                req.SetRequestHeader("Content-Type", "application/json; charset=UTF-8")
                req.Send(bodyObj)
            } else {
                if (!InStr(cleanUrl, "/chat/completions"))
                    cleanUrl .= "/chat/completions"

                bodyObj := '{"model":' . this.EscapeJSON(model) 
                    . ',"messages":['
                    . '{"role":"system","content":' . this.EscapeJSON(systemPrompt) . '},'
                    . '{"role":"user","content":' . this.EscapeJSON(text) . '}'
                    . '],"temperature":0.3}'

                req.Open("POST", cleanUrl, false)
                req.SetRequestHeader("Content-Type", "application/json; charset=UTF-8")
                req.SetRequestHeader("Authorization", "Bearer " . apiKey)
                req.Send(bodyObj)
            }

            if (req.Status != 200) {
                return "【接口返回异常 HTTP " . req.Status . "】: " . SubStr(req.ResponseText, 1, 100)
            }

            resText := req.ResponseText
            out := this.ExtractResponseContent(resText)
            return Trim(out, ' `t`r`n"')
        } catch as err {
            return "【网络连接失败】: " . err.Message
        }
    }

    static ExtractResponseContent(respJson) {
        if RegExMatch(respJson, 's)"content"\s*:\s*"((?:[^"\\]|\\.)*)"', &m) {
            return this.UnescapeJSON(m[1])
        }
        if RegExMatch(respJson, 's)"text"\s*:\s*"((?:[^"\\]|\\.)*)"', &mText) {
            return this.UnescapeJSON(mText[1])
        }
        return respJson
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
        str := StrReplace(str, "\\", "\")
        str := StrReplace(str, "\n", "`n")
        str := StrReplace(str, "\r", "`r")
        str := StrReplace(str, "\t", "`t")
        return str
    }

    static MapToJSON(mapObj) {
        if !IsObject(mapObj)
            return '""'
        
        json := "{"
        first := true
        for k, v in mapObj {
            if (!first)
                json .= ","
            first := false
            json .= '"' . k . '":'
            if (IsObject(v)) {
                if (v is Map)
                    json .= this.MapToJSON(v)
                else if (v is Array) {
                    json .= "["
                    arrFirst := true
                    for item in v {
                        if (!arrFirst) json .= ","
                        arrFirst := false
                        json .= '"' . item . '"'
                    }
                    json .= "]"
                }
            } else if (v is Integer || v is Float) {
                json .= v
            } else if (Type(v) == "Boolean") {
                json .= v ? "true" : "false"
            } else {
                json .= this.EscapeJSON(String(v))
            }
        }
        json .= "}"
        return json
    }
}