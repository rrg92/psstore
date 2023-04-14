<#
	Este script implementa algumas funções simples para facilitar sua interação com a API da OpenAI!
	O objetivo deste script é mostrar como você pode facilmente invocar a API do OpenAI com PowerShell, ao mesmo tempo que prover uma interface simples para 
	as chamadas mais importantes.  
	
	Antes de continuar, o que você precisa?
	
		Gere um token no site da OpenAI!
		Coloca na variável de ambiente OPENAI_API_KEY.
		
	Exemplo de como usar:
	
		> $Env:OPENAI_API_KEY = "MeuToken"
		> . Caminho\Openai.ps1
		> $res = OpenAiTextCompletion "Olá, estou falando com você direto do PowerShell"
		> $res.choices[0].text
		
	Verifique os comentáros em cada funçã abaixo para mais informações!
	
	ATENÇÃO: LEMBRE-SE que as chamadas realizadas irão consumir seus créditos da OpenAI!  
	Certifique-se que você compreendeu o modelo de cobrança da OpenAI para evitar surpresas.  
	Além disso, esta é uma versão sem testes e para uso livre por sua própria conta e risco.
#>


<#
	Esta função é usada como base para invocar a a API da OpenAI!
#>
function InvokeOpenai {
    param($endpoint, $body, $token = $Env:OPENAI_API_KEY)


    if(!$token){
        throw "OPENAI_NO_KEY";
    }

    $ReqBody = $body | ConvertTo-Json;
    $headers = @{
        "Authorization" = "Bearer $token"
    }
    
    $url = "https://api.openai.com/v1/$endpoint"

    $ReqParams = @{
        body            = $ReqBody
        ContentType     = "application/json; charset=utf-8"
        Uri             = $url
        Method          = 'POST'
        UseBasicParsing = $true
        Headers         = $headers
    }

    $RawResp 	= Invoke-WebRequest @ReqParams
    $result 	= [System.Text.Encoding]::UTF8.GetString($RawResp.RawContentStream.ToArray())
    
    $ResponseResult = $result | ConvertFrom-Json

    return $ResponseResult;
}

<#
	Esta função chama o endpoint /completions (https://platform.openai.com/docs/api-reference/completions/create)
	Exemplo:
		$res = OpenAiTextCompletion "Gere um nome aleatorio"
		$res.choices[0].text;
	
	Ela retorna o mesmo objeto retornado pela API da OpenAI!
	Por enquanto, apenas os parâmetros temperature, model e MaxTokens foram implementados!
#>
function OpenAiTextCompletion {
    param(
            $prompt 
            ,$temperature   = 0.6
            ,$model         = "text-davinci-003"
            ,$MaxTokens     = 200
    )

    $FullPrompt = @($prompt) -Join "`n";

    $Body = @{
        model       = $model
        prompt      = $FullPrompt
        max_tokens  = $MaxTokens
        temperature = $temperature 
    }

    InvokeOpenai -endpoint 'completions' -body $Body
}


<#
	Esta função chama o endpoint /chat/completions (https://platform.openai.com/docs/api-reference/chat/create)
	Este endpoint permite você conversar com modelos mais avançados como o GPT-3 e o GPT-4 (veja a disponiblidadena doc)
	
	O Chat Completion tem uma forma de conversa um pouco diferente do que o Text Completion.  
	No Chat Completion, você pode especificar um role, que é uma espécie de categorização do autor da mensagem.  
	
	A API suporta 3 roles:
		user 
			Representa um prompt genérico do usuário.
			
		system
			Representa uma mensagem de controle, que pode dar instruções que o modelo vai levar em conta para gerar a resposta.
			
		assistant
			Representa mensagens prévias. É útil para que o modelo possa aprender como gerar, entender o contexto, etc.  
			
	Basicamente, o system e o assistant são úteis para calibrar melhor a resposta.  
	Enquanto que o user, é o que de fato você quer de resposta (você, ou o seu usuário)
	
	
	Nesta função, para tentar facilitar sua vida, eu deixei duas formas pela qual você usar.  
	A primeira forma é a mais simples:
	
		$res = OpenAiChat "Oi GPT, tudo bem?"
		$res.choices[0].message;
		
		Nesta forma, você passa apenas uma mensagem padrão, e a função vai cuidar de enviar como o role "user".
		Você pode passar várias linhas de texto, usando um simples array do PowerShell:
		
		$res = OpenAiChat "Oi GPT, tudo bem?","Me de uma dica aleatoria sobre o PowerShell"
		
		Isso vai enviar o seguinte prompt ao modelo:
			Oi,GPT, tudo bem?
			Me de uma dica aleatoria sobre o PowerShell
		
		
	Caso, você queria especificar um role, basta usar um dos prefixos. (u - user, s - system, a - assitant"
	
		$res = OpenAiChat "s: Use muita informalidade e humor!","u: Olá, me explique o que é o PowerShell!"
		$res.choices[0].message.content;
	
	Você pode usar um array no script:
	
		$Prompt = @(
			'a: function Abc($p){ return $p*100 }'
			"s: Gere uma explicação bastante dramática com no máximo 100 palavras!"
			"Me explique o que a função Abc faz!"
		)
		
		$res = OpenAiChat $Prompt -MaxTokens 1000
		
		DICA: Note que na última mensagem, e não precisei especificar o "u: mensagem", visto que ele ja usa como default se não encontra o prefixo.
		DICA 2: Note que eu usei o parâmetro MaxTokens para aumentar o limite padrão de 200.
#>
function OpenAiChat {
    param(
         $prompt
        ,$temperature   = 0.6
        ,$model         = "gpt-3.5-turbo"
        ,$MaxTokens     = 200
    )

    $Messages = @();

    $ShortRoles = @{
        s = "system"
        u = "user"
        a = "assistant"
    }

    [string[]]$InputMessages =@($prompt);
    foreach($m in $InputMessages){
        
        if($m -match '(?s)([s|u|a]): (.+)'){
            $ShortName  = $matches[1];
            $Content    = $matches[2];

            $RoleName = $ShortRoles[$ShortName];

            if(!$RoleName){
                $RoleName   = "user"
                $Content    = $m;
            }
        } else {
            $RoleName   = "user";
            $Content    = $m;
        }
        
        $Messages += @{role = $RoleName; content = $Content};
    }

    $Body = @{
        model       = $model
        messages    = $Messages 
        max_tokens  = $MaxTokens
        temperature = $temperature 
    }

    InvokeOpenai -endpoint 'chat/completions' -body $Body
}