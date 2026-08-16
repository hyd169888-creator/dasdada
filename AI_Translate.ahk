#Requires AutoHotkey v2.0

class AITranslate {
    static Execute(text, cfg) {
        apiKey := cfg.Has("api_key") ? cfg["api_key"] : ""
        baseUrl := cfg.Has("base_url") ? cfg["base_url"] : "https://integrate.api.nvidia.com/v1"
        model := cfg.Has("model") ? cfg["model"] : "meta/llama-3.1-8b-instruct"
        targetLang := cfg.Has("target_lang") ? cfg["target_lang"] : "en"

        if (apiKey == "") {
            MsgBox("请先在设置中心配置 API Key！", "提示", "Icon!")
            return ""
        }

        systemPrompt := "You are a professional, direct translator. Translate the user input into the target language (" . targetLang . ") naturally and accurately. Output ONLY the translated text without explanations, greetings, quotes, or notes."

        bodyMap := Map(
            "model", model,
            "messages", [
                Map("role", "system", "content", systemPrompt),
                Map("role", "user", "content", text)
            ],
            "temperature", 0.3
        )

        bodyJson := this._MapToJson(bodyMap)

        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.SetTimeouts(5000, 5000, 15000, 15000)
            http.Open("POST", baseUrl . "/chat/completions", false)
            http.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
            http.SetRequestHeader("Authorization", "Bearer " . apiKey)
            http.Send(bodyJson)

            if (http.Status == 200) {
                resp := http.ResponseText
                if RegExMatch(resp, 's)"content"\s*:\s*"(.*?)"(?:\s*,\s*"|\s*\})', &m) {
                    content := m[1]
                    content := StrReplace(content, "\n", "`n")
                    content := StrReplace(content, '\"', '"')
                    content := StrReplace(content, "\\", "\")
                    return Trim(content)
                }
            }
        } catch {
        }
        return ""
    }

    static _MapToJson(obj) {
        if (Type(obj) == "Map") {
            pairs := []
            for k, v in obj {
                pairs.Push('"' . k . '":' . this._MapToJson(v))
            }
            return "{" . this._Join(pairs, ",") . "}"
        } else if (Type(obj) == "Array") {
            items := []
            for item in obj {
                items.Push(this._MapToJson(item))
            }
            return "[" . this._Join(items, ",") . "]"
        } else if (Type(obj) == "String") {
            escaped := StrReplace(obj, "\", "\\")
            escaped := StrReplace(escaped, '"', '\"')
            escaped := StrReplace(escaped, "`n", "\n")
            escaped := StrReplace(escaped, "`r", "\r")
            escaped := StrReplace(escaped, "`t", "\t")
            return '"' . escaped . '"'
        } else if (Type(obj) == "Integer" || Type(obj) == "Float") {
            return String(obj)
        }
        return '""'
    }

    static _Join(arr, delimiter) {
        res := ""
        for idx, val in arr {
            res .= (idx > 1 ? delimiter : "") . val
        }
        return res
    }
}