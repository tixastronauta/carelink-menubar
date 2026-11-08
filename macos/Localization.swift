import Foundation

/// App language chosen in Settings. `system` follows macOS: Portuguese if the first preferred
/// language is Portuguese, English otherwise.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, portuguese = "pt", english = "en"
    var id: String { rawValue }
}

/// Minimal in-app localization, switchable at runtime without restarting.
/// Source strings are European Portuguese and double as keys; `english` holds translations.
/// Keys with arguments use %@ placeholders (pass numbers as String).
enum L10n {
    static var choice: AppLanguage = .system

    static var isEnglish: Bool {
        switch choice {
        case .english: return true
        case .portuguese: return false
        case .system: return !(Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("pt")
        }
    }
    /// Locale for numbers and dates in the chosen language.
    static var locale: Locale { Locale(identifier: isEnglish ? "en_GB" : "pt_PT") }

    static func lookup(_ key: String) -> String { isEnglish ? (english[key] ?? key) : key }

    static let english: [String: String] = [
        // Menu bar and menus
        "CareLink: glicemia e tendência": "CareLink: glucose and trend",
        "sem unidade": "no unit",
        "leitura %@": "reading %@",
        "%@ %@ às %@": "%@ %@ at %@",
        "clicar para detalhes": "click for details",
        "Abrir": "Open",
        "Definições…": "Settings…",
        "Sair": "Quit",
        "Terminar sessão no CareLink?": "Sign out of CareLink?",
        "Remove a sessão deste Mac e limpa os dados apresentados. Para voltar a ver dados, tens de entrar novamente.":
            "Removes the session from this Mac and clears the data shown. To see data again, you will need to sign in again.",
        "Terminar sessão": "Sign Out",
        "Cancelar": "Cancel",

        // Model
        "Tendência a subir": "Trending up",
        "Tendência a descer": "Trending down",
        "Sem seta de tendência reportada": "No trend arrow reported",
        "Ativo": "Active",
        "Basal segura": "Safe Basal",
        "Basal segura (%@min)": "Safe Basal (%@min)",
        "Desligado (manual)": "Off (manual)",
        "Sensor a aquecer": "Sensor warming up",
        "Trocar sensor": "Change sensor",
        "Calibração necessária": "Calibration required",
        "Não calibrar agora": "Do not calibrate now",
        "Sensor abaixo de 40 mg/dL": "Sensor below 40 mg/dL",
        "Sensor: %@": "Sensor: %@",
        "Trocar conjunto": "Change infusion set",
        "Telemóvel sem ligação ao CareLink": "Phone not connected to CareLink",
        "Bomba fora do alcance do telemóvel": "Pump out of range of the phone",
        "no futuro": "in the future",
        "agora": "now",
        "há %@min": "%@min ago",
        "há %@h": "%@h ago",
        "há %@h %@min": "%@h %@min ago",
        "em %@min": "in %@min",
        "em %@h": "in %@h",
        "em %@h %@min": "in %@h %@min",
        "Hora da leitura indisponível": "Reading time unavailable",
        "Hora da leitura à frente do relógio do Mac": "Reading time is ahead of the Mac's clock",
        "Última leitura %@": "Last reading %@",
        "Bólus": "Bolus",
        "Correção automática": "Auto correction",
        "Hidratos": "Carbs",

        // Errors and status messages
        "A sessão expirou ou não foi aceite. Volta a entrar no CareLink.": "The session expired or was not accepted. Sign in to CareLink again.",
        "A configuração europeia do CareLink mudou ou a conta pertence a outra região.": "CareLink's European configuration changed, or the account belongs to another region.",
        "O CareLink devolveu um formato de dados não reconhecido.": "CareLink returned an unrecognised data format.",
        "Não foi possível contactar o CareLink. Verifica a ligação e tenta novamente.": "Could not reach CareLink. Check the connection and try again.",
        "Esta versão precisa de uma conta com exatamente um paciente associado.": "This version needs an account with exactly one linked patient.",
        "Não foi possível aceder ao Porta-chaves. Autoriza o acesso à sessão desta app.": "Could not access the Keychain. Allow this app to access its session.",
        "Início de sessão cancelado.": "Sign-in cancelled.",
        "A consulta demorou demasiado. Tenta atualizar novamente.": "The request took too long. Try refreshing again.",
        "Não foi possível remover a sessão do Porta-chaves. Tenta Terminar sessão novamente.": "Could not remove the session from the Keychain. Try Sign Out again.",
        "Não foi possível alterar o arranque automático. Confirma em Definições do Sistema → Geral → Itens de início de sessão.":
            "Could not change launch at login. Check System Settings → General → Login Items.",

        // Notifications
        "CareLink: sessão expirada": "CareLink: session expired",
        "Volta a entrar no CareLink para continuar a ver os dados.": "Sign in to CareLink again to keep seeing your data.",
        "CareLink: sem leituras novas": "CareLink: no new readings",
        "A última leitura tem %@min. Verifica o telemóvel, a bomba e o sensor.": "The last reading is %@min old. Check the phone, pump and sensor.",

        // Panel
        "Tempo na faixa": "Time in range",
        "%@, últimas 24h": "%@, last 24h",
        "Abaixo": "Below",
        "Acima": "Above",
        "Média %@ %@": "Average %@ %@",
        "Tempo na faixa %@, abaixo %@, acima %@, últimas 24 horas": "Time in range %@, below %@, above %@, last 24 hours",
        "Atualizar agora": "Refresh now",
        "Copiar imagem do painel": "Copy panel image",
        "Copiado": "Copied",
        "Definições": "Settings",
        "Volta a entrar no CareLink": "Sign in to CareLink again",
        "Liga a tua conta CareLink": "Connect your CareLink account",
        "Entra na página oficial do CareLink europeu. A sessão fica guardada no Porta-chaves deste Mac.":
            "Sign in on the official European CareLink page. The session is stored in this Mac's Keychain.",
        "A aguardar autenticação…": "Waiting for authentication…",
        "Entrar no CareLink": "Sign In to CareLink",
        "Tendência indisponível": "Trend unavailable",
        "Insulina ativa": "Active insulin",
        "Leitura do sensor": "Sensor reading",
        "Última atualização": "Last update",
        "Próxima atualização": "Next update",
        "Insulina no reservatório": "Insulin in the reservoir",
        "Bateria da bomba": "Pump battery",
        "Tempo restante do sensor": "Sensor time remaining",
        "Tempo até trocar o conjunto de infusão": "Time until the infusion set change",
        "Reservatório": "Reservoir",
        "Bateria": "Battery",
        "Conjunto": "Infusion set",
        "Sensor": "Sensor",
        "Trocar": "Change",
        "Bomba suspensa": "Pump suspended",
        "A carregar": "Charging",
        "Histórico": "History",
        "Hora": "Time",
        "Glicemia": "Glucose",
        "Limite inferior": "Lower limit",
        "Limite superior": "Upper limit",
        "Histórico de glicemia em linha, últimas %@ horas disponíveis": "Glucose history line chart, last %@ hours available",
        "Histórico insuficiente para desenhar o gráfico.": "Not enough history to draw the chart.",

        // Settings: tabs and sections
        "Geral": "General",
        "Apresentação": "Display",
        "Gráfico": "Chart",
        "Conta": "Account",
        "Avançado": "Advanced",
        "Sobre": "About",
        "Idioma": "Language",
        "Automático (macOS)": "Automatic (macOS)",
        "Arranque": "Startup",
        "Atualização": "Updates",
        "Notificações": "Notifications",
        "Valor da glicemia": "Glucose value",
        "Painel": "Panel",
        "Faixa-alvo": "Target range",
        "No gráfico": "On the chart",
        "Conta CareLink": "CareLink account",
        "Modo diagnóstico": "Diagnostic mode",
        "Estrutura do payload": "Payload structure",
        "Mais informação": "More information",

        // Settings: General
        "Abrir ao iniciar sessão no Mac": "Open at Mac login",
        "Falta aprovar nas Definições do Sistema.": "Approval needed in System Settings.",
        "Abrir Definições do Sistema": "Open System Settings",
        "Atualizar a cada": "Refresh every",
        "%@min": "%@min",
        "Avisar falhas técnicas": "Notify technical problems",
        "info.language": "Automatic follows the macOS language: Portuguese if macOS is in Portuguese, English otherwise. The change applies immediately.",
        "info.launch": "The app opens by itself when you log in to the Mac, with the panel closed. macOS may ask you to approve it in System Settings → General → Login Items.",
        "info.refresh": "The sensor sends a value every 5min. With 5min you see more recent readings, but the app makes twice as many requests to CareLink. When a reading gets old, the app refreshes right away, at most every 2min.",
        "info.notifications": "macOS notification when the session expires, when there have been no new readings for more than 30min, or when the sensor (under 24h and 6h left) or infusion set (under 12h and 2h) is ending. These are not glucose alerts and do not replace the pump or MiniMed app alarms.",

        // Settings: Display
        "Colorir quando está fora da faixa-alvo": "Colour when outside the target range",
        "Mostrar seta de tendência na barra de menus": "Show trend arrow in the menu bar",
        "Estado do SmartGuard": "SmartGuard status",
        "Reservatório, bateria, sensor e conjunto": "Reservoir, battery, sensor and infusion set",
        "Avisos do sensor": "Sensor messages",
        "Avisos de ligação do telemóvel e da bomba": "Phone and pump connection messages",
        "Os avisos de leitura antiga e de erros de ligação ao CareLink aparecem sempre.": "Old-reading warnings and CareLink connection errors are always shown.",
        "info.color": "In the menu bar and the panel: orange outside the target range, red below 54 mg/dL. The target range is set in the Chart tab.",
        "info.tir": "Share of the last 24h between 70 and 180 mg/dL, calculated by CareLink. It always uses this standard range, not your target range. Green from 70%, the goal in international guidelines.",
        "info.smartguard": "The pump's automatic mode. Active: the pump adjusts insulin by itself. Safe Basal: temporary safety mode, with the time remaining. Off: manual mode.",
        "info.device": "Insulin in the reservoir, pump battery, sensor time remaining and a reminder to change the infusion set. Sensor time turns orange under 24h and red under 6h; infusion set under 12h and 2h. Also shows when the pump is suspended or charging.",
        "info.sensor": "Sensor messages reported by CareLink, such as warm-up, calibration required or change sensor. Only shown when there is a problem.",
        "info.connection": "When the reading is old, shows whether the phone lost its connection to CareLink or the pump is out of range of the phone.",

        // Settings: Chart
        "Usada na banda do gráfico e nas cores. Não altera o tempo na faixa nem gera alertas.": "Used for the chart band and colours. It does not change time in range or create alerts.",
        "Repor 70–180": "Reset to 70–180",
        "Usar os limites de alerta da bomba": "Use the pump's alert limits",
        "Limites da bomba": "Pump limits",
        "Indisponível": "Unavailable",
        "info.pumplimits": "Uses the low and high glucose alert limits set on the pump instead of the manual limits, and follows any change made on the pump. These are alert limits, often wider than a target. Time in range always uses 70–180 mg/dL.",
        "Média": "Average",
        "Média, CV e GMI": "Average, CV and GMI",
        "Mini-gráfico na barra de menus": "Mini chart in the menu bar",
        "Mini-gráfico das últimas 3h": "Mini chart of the last 3h",
        "info.stats": "Shows the average, coefficient of variation and GMI of the last 24h under the time in range card. Hover each value for an explanation.",
        "info.sparkline": "Small line with the last 3h of readings next to the value in the menu bar. Hidden when the reading is old.",
        "info.mean": "Average of the readings in the last 24h, calculated by the app.",
        "info.cv": "Coefficient of variation: how much glucose varies around the average (standard deviation %@). Below 36% is usually considered stable.",
        "info.gmi": "Glucose Management Indicator: an HbA1c estimate from the average glucose. With only 24h of data it is indicative; the clinical value uses 14 days or more.",
        "Banda da faixa-alvo": "Target range band",
        "Pontos nas leituras fora da faixa": "Dots on readings outside the range",
        "Bólus e refeições": "Boluses and meals",
        "Correções automáticas do SmartGuard": "SmartGuard auto corrections",
        "info.band": "Green area on the chart between the target range limits.",
        "info.points": "Marks readings outside the target range with a dot: orange outside the range, red below 54 mg/dL.",
        "info.markers": "Symbols at the bottom of the chart: a drop for boluses, fork and knife for carbs. Hover over a symbol to see the amount and time.",
        "info.autocorrections": "Small boluses that SmartGuard gives by itself, many times a day. Turn off for a cleaner chart.",

        // Settings: Account
        "Sessão expirada": "Session expired",
        "Sem sessão": "Not signed in",
        "Entrar novamente": "Sign In Again",
        "Terminar sessão…": "Sign Out…",

        "A ligar ao CareLink…": "Connecting to CareLink…",
        "Conclui o início de sessão na página oficial.": "Finish signing in on the official page.",
        "Ligado ao CareLink": "Connected to CareLink",
        "Entra novamente para continuar a ver os dados.": "Sign in again to keep seeing your data.",
        "Entra na página oficial do CareLink para ver os teus dados.": "Sign in on the official CareLink page to see your data.",

        // Settings: Advanced
        "Guardar respostas do CareLink": "Save CareLink responses",
        "Diagnóstico": "Diagnostics",
        "info.diagnosticsbadge": "Diagnostic mode is on: CareLink responses are being saved on this Mac. Turn it off in Settings → Advanced.",
        "Inclui dados de saúde e a tua identidade. Os tokens nunca são guardados.": "Includes health data and your identity. Tokens are never saved.",
        "Abrir pasta dos logs": "Open Logs Folder",
        "Apagar logs": "Delete Logs",
        "Copiar estrutura do payload": "Copy Payload Structure",
        "info.diagnostics": "Writes every CareLink response to ~/Library/Logs/CareLink Menubar, on this Mac only. Useful while developing. Stays on until you turn it off, with a “Diagnostics” badge in the panel. Logs older than 7 days are deleted.",
        "info.shape": "Copies only the field names and types of the last reading, without values. Useful to see which data CareLink sends. Available after a refresh.",

        // Consumable life
        "Trocar sensor em breve": "Change the sensor soon",
        "Trocar conjunto em breve": "Change the infusion set soon",
        "Sensor termina em %@": "Sensor ends in %@",
        "Conjunto termina em %@": "Infusion set ends in %@",
        "Está na altura de trocar o conjunto de infusão": "Time to change the infusion set",
        "CareLink: trocar sensor em breve": "CareLink: change the sensor soon",
        "CareLink: o sensor está a terminar": "CareLink: the sensor is ending",
        "CareLink: trocar conjunto em breve": "CareLink: change the infusion set soon",
        "CareLink: o conjunto está a terminar": "CareLink: the infusion set is ending",
        "Faltam %@ para o fim do sensor.": "%@ left until the sensor ends.",
        "Faltam %@ para trocar o conjunto de infusão.": "%@ left until the infusion set change.",

        // Widget
        "Widget": "Widget",
        "Mostrar dados no widget da secretária": "Show data in the desktop widget",
        "Abre o CareLink Menubar": "Open CareLink Menubar",
        "na faixa, 24h": "in range, 24h",
        "Glicemia, tendência e gráfico das últimas 3h.": "Glucose, trend and chart of the last 3h.",
        "info.widget": "The app saves a summary of the latest reading (value, trend, last 3h and time in range) in a folder shared only with its widget, on this Mac. Turning this off deletes the file and the widget shows “—”. Add the widget by right-clicking the desktop → Edit Widgets.",

        // Consent
        "Antes de começar": "Before you start",
        "Consentimento para utilizar o CareLink Menubar": "Consent to use CareLink Menubar",
        "Aceito e quero continuar": "I Agree and Continue",
        "Consentimento": "Consent",
        "Aceite em": "Accepted on",
        "Retirar consentimento…": "Withdraw Consent…",
        "Retirar o consentimento?": "Withdraw consent?",
        "Retirar e sair": "Withdraw and Quit",
        "Retirar termina a sessão, apaga os ficheiros guardados pela app e fecha-a.": "Withdrawing signs out, deletes the files saved by the app and quits it.",
        "consent.read": "To work, CareLink Menubar reads your health data from your CareLink account, such as glucose, insulin and pump and sensor status, through automated systems.",
        "consent.store": "This data may be saved in files on this Mac, for example to show the latest reading in a widget or for diagnostics.",
        "consent.sharing": "The app does not actively share this data with any entity: it only stays on this Mac's disk.",
        "consent.responsibility": "You are responsible for protecting this Mac and for keeping this data and these files intact and not sharing them with others.",
        "consent.unofficial": "This is an unofficial app, not affiliated with MiniMed (formerly Medtronic Diabetes). It does not replace your pump, sensor or the MiniMed app, nor their alarms. Always confirm values in the official app.",
        "consent.withdraw": "This signs out of CareLink, deletes the files saved by the app on this Mac and quits. The next time you open the app, it will ask for consent again.",

        // Settings: About
        "Versão": "Version",
        "Licença": "Licence",
        "Código-fonte no GitHub": "Source code on GitHub",
        "Projeto original": "Original project",
        "App não oficial, sem afiliação à MiniMed (antiga Medtronic Diabetes). Apenas leitura: não controla a bomba nem substitui a app MiniMed. Confirma sempre os valores na app oficial.":
            "Unofficial app, not affiliated with MiniMed (formerly Medtronic Diabetes). Read-only: it does not control the pump or replace the MiniMed app. Always confirm values in the official app.",
    ]

    /// Portuguese text for keys that are identifiers rather than source sentences.
    static let portugueseInfo: [String: String] = [
        "info.language": "Automático segue o idioma do macOS: português se o macOS estiver em português, inglês nos restantes casos. A alteração aplica-se logo.",
        "info.launch": "A app abre sozinha quando inicias sessão no Mac, com o painel fechado. O macOS pode pedir para aprovares em Definições do Sistema → Geral → Itens de início de sessão.",
        "info.refresh": "O sensor envia um valor a cada 5min. Com 5min vês leituras mais recentes, mas a app faz o dobro dos pedidos ao CareLink. Quando a leitura fica antiga, a app atualiza logo, no máximo a cada 2min.",
        "info.notifications": "Notificação do macOS quando a sessão expira, quando não há leituras novas há mais de 30min, ou quando o sensor (menos de 24h e de 6h) ou o conjunto de infusão (menos de 12h e de 2h) está a terminar. Não são alertas de glicemia e não substituem os alarmes da bomba nem da app MiniMed.",
        "info.color": "Na barra de menus e no painel: laranja fora da faixa-alvo, vermelho abaixo de 54 mg/dL. A faixa-alvo define-se no separador Gráfico.",
        "info.tir": "Percentagem das últimas 24h entre 70 e 180 mg/dL, calculada pelo CareLink. Usa sempre esta faixa padrão, não a tua faixa-alvo. Verde a partir de 70%, o objetivo das recomendações internacionais.",
        "info.smartguard": "Modo automático da bomba. Ativo: a bomba ajusta a insulina sozinha. Basal segura: modo de segurança temporário, com o tempo restante. Desligado: modo manual.",
        "info.device": "Insulina no reservatório, bateria da bomba, tempo restante do sensor e aviso para trocar o conjunto de infusão. O tempo do sensor fica laranja com menos de 24h e vermelho com menos de 6h; o do conjunto com menos de 12h e de 2h. Também mostra se a bomba está suspensa ou a carregar.",
        "info.sensor": "Mensagens do sensor indicadas pelo CareLink, como aquecimento, calibração necessária ou trocar sensor. Só aparecem quando há um problema.",
        "info.connection": "Quando a leitura está antiga, indica se o telemóvel perdeu a ligação ao CareLink ou se a bomba ficou fora do alcance do telemóvel.",
        "info.band": "Área verde no gráfico entre os limites da faixa-alvo.",
        "info.points": "Marca com um ponto as leituras fora da faixa-alvo: laranja fora da faixa, vermelho abaixo de 54 mg/dL.",
        "info.markers": "Símbolos no fundo do gráfico: gota para bólus, garfo e faca para hidratos. Passa o rato por cima de um símbolo para ver a quantidade e a hora.",
        "info.autocorrections": "Pequenos bólus que o SmartGuard dá sozinho, muitas vezes por dia. Desliga para um gráfico mais limpo.",
        "info.diagnostics": "Grava cada resposta do CareLink em ~/Library/Logs/CareLink Menubar, só neste Mac. Útil durante o desenvolvimento. Fica ligado até o desligares, com o aviso “Diagnóstico” no painel. Os logs com mais de 7 dias são apagados.",
        "info.diagnosticsbadge": "O modo diagnóstico está ligado: as respostas do CareLink estão a ser guardadas neste Mac. Desliga-o em Definições → Avançado.",
        "info.pumplimits": "Usa os limites de alerta de glicemia baixa e alta configurados na bomba, em vez dos limites manuais, e acompanha as alterações feitas na bomba. São limites de alerta, muitas vezes mais largos do que um alvo. O tempo na faixa usa sempre 70–180 mg/dL.",
        "info.stats": "Mostra a média, o coeficiente de variação e o GMI das últimas 24h por baixo do cartão do tempo na faixa. Passa o rato por cada valor para ver a explicação.",
        "info.sparkline": "Pequena linha com as leituras das últimas 3h ao lado do valor na barra de menus. Desaparece quando a leitura está antiga.",
        "info.mean": "Média das leituras das últimas 24h, calculada pela app.",
        "info.cv": "Coeficiente de variação: quanto a glicemia varia em torno da média (desvio padrão %@). Abaixo de 36% é normalmente considerado estável.",
        "info.gmi": "Indicador de gestão da glicemia: estimativa da HbA1c a partir da média. Com só 24h de dados é indicativo; o valor clínico usa 14 dias ou mais.",
        "info.widget": "A app guarda um resumo da última leitura (valor, tendência, últimas 3h e tempo na faixa) numa pasta partilhada só com o seu widget, neste Mac. Desligar apaga o ficheiro e o widget passa a mostrar “—”. Para adicionar o widget: botão direito na secretária → Editar widgets.",
        "consent.read": "Para funcionar, o CareLink Menubar lê os teus dados de saúde da conta CareLink, como a glicemia, a insulina e o estado da bomba e do sensor, através de sistemas automáticos.",
        "consent.store": "Estes dados podem ficar guardados em ficheiros neste Mac, por exemplo para mostrar a última leitura num widget ou para diagnóstico.",
        "consent.sharing": "A app não partilha ativamente estes dados com nenhuma entidade: ficam apenas no disco deste Mac.",
        "consent.responsibility": "És responsável por proteger este Mac e por zelar pela integridade destes dados e ficheiros, não os partilhando com terceiros.",
        "consent.unofficial": "Esta app não é oficial nem tem afiliação à MiniMed (antiga Medtronic Diabetes). Não substitui a bomba, o sensor nem a app MiniMed, nem os respetivos alarmes. Confirma sempre os valores na app oficial.",
        "consent.withdraw": "Termina a sessão no CareLink, apaga os ficheiros guardados pela app neste Mac e fecha-a. Da próxima vez que abrires a app, será pedido de novo o consentimento.",
        "info.shape": "Copia só os nomes e tipos dos campos da última leitura, sem valores. Útil para perceber que dados o CareLink envia. Disponível depois de uma atualização.",
    ]
}

/// Translates a Portuguese source string (or an `info.` identifier) to the current language.
func tr(_ key: String) -> String {
    if !L10n.isEnglish, let portuguese = L10n.portugueseInfo[key] { return portuguese }
    return L10n.lookup(key)
}

/// Translates a key with %@ placeholders and fills them in order.
func tr(_ key: String, _ arguments: String...) -> String {
    var result = tr(key)
    for argument in arguments {
        guard let range = result.range(of: "%@") else { break }
        result.replaceSubrange(range, with: argument)
    }
    return result
}
