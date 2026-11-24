"""App Store listing copy for every language. Used by tools/asc_listing.py."""

PRIVACY = "https://winniecherian.github.io/rainpulse/privacy.html"
SUPPORT = "https://winniecherian.github.io/rainpulse/support.html"
MARKETING = "https://winniecherian.github.io/rainpulse/"
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
COPYRIGHT = "2026 NeuralOrbitX"

def desc(t):
    """Build a description from translated parts."""
    return f"""{t['hook']}

{t['intro']}

{t['h1']}
• {t['b1']}
• {t['b2']}
• {t['b3']}

{t['h2']}
• {t['b4']}
• {t['b5']}
• {t['b6']}
• {t['b7']}

{t['h3']}
• {t['b8']}
• {t['b9']}

{t['h4']}
• {t['b10']}
• {t['b11']}
• {t['b12']}

{t['h5']}
{t['plans']}

{t['data']}: Apple Weather, OpenWeather, NOAA, GDACS, Open-Meteo.
{t['terms']}: {EULA}
{t['privacy']}: {PRIVACY}"""

EN = dict(
    hook="Know exactly when it rains.",
    intro="RainPulse shows rain starting and stopping, minute by minute, wherever you are. Glance at the Rain Clock, check the live radar, and get a heads-up before rain reaches you.",
    h1="THE ESSENTIALS, AT A GLANCE",
    b1="Rain Clock: the next 2 hours as a dial. When rain starts, how hard, and when it stops",
    b2="Rain, snow, wind and air quality on one clean screen",
    b3="Hourly and 14-day forecasts for every city in the world",
    h2="LIVE RADAR",
    b4="Bold rain colours on a dark map, anywhere on Earth",
    b5="Rain forecast animation up to 48 hours ahead",
    b6="Clouds, wind, temperature and pressure layers",
    b7="Animated wind flow",
    h3="ALERTS THAT MATTER",
    b8="Rain alerts for your location and saved places",
    b9="Cyclone tracker with storm tracks, forecast cones and alerts",
    h4="PRIVATE BY DESIGN",
    b10="No account, no ads, no tracking",
    b11="Optional Face ID lock",
    b12="AI insights run on your iPhone",
    h5="PLANS",
    plans="RainPulse is free to use. Essential and Pro unlock the minute-by-minute rain chart, longer forecasts, alerts for up to 20 places, extra map layers and AI insights. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel any time in your Apple Account settings.",
    data="Weather data", terms="Terms of Use", privacy="Privacy Policy",
)

ES = dict(
    hook="Sabe exactamente cuándo va a llover.",
    intro="RainPulse te muestra cuándo empieza y cuándo para la lluvia, minuto a minuto, estés donde estés. Mira el Reloj de Lluvia, consulta el radar en vivo y recibe un aviso antes de que la lluvia llegue.",
    h1="LO ESENCIAL, DE UN VISTAZO",
    b1="Reloj de Lluvia: las próximas 2 horas en un dial. Cuándo empieza, con qué fuerza y cuándo para",
    b2="Lluvia, nieve, viento y calidad del aire en una sola pantalla limpia",
    b3="Pronóstico por horas y de 14 días para cualquier ciudad del mundo",
    h2="RADAR EN VIVO",
    b4="Colores de lluvia intensos sobre un mapa oscuro, en todo el planeta",
    b5="Animación del pronóstico de lluvia hasta 48 horas",
    b6="Capas de nubes, viento, temperatura y presión",
    b7="Flujo de viento animado",
    h3="ALERTAS QUE IMPORTAN",
    b8="Alertas de lluvia para tu ubicación y tus lugares guardados",
    b9="Seguimiento de ciclones con trayectorias, conos de pronóstico y alertas",
    h4="PRIVACIDAD DESDE EL DISEÑO",
    b10="Sin cuenta, sin anuncios, sin rastreo",
    b11="Bloqueo opcional con Face ID",
    b12="La IA funciona en tu iPhone",
    h5="PLANES",
    plans="RainPulse es gratis. Essential y Pro desbloquean el gráfico de lluvia minuto a minuto, pronósticos más largos, alertas para hasta 20 lugares, capas de mapa adicionales e información con IA. Las suscripciones se renuevan automáticamente salvo que se cancelen al menos 24 horas antes del final del periodo. Gestiona o cancela en los ajustes de tu cuenta de Apple.",
    data="Datos meteorológicos", terms="Términos de uso", privacy="Política de privacidad",
)

PT = dict(
    hook="Saiba exatamente quando vai chover.",
    intro="O RainPulse mostra quando a chuva começa e para, minuto a minuto, onde você estiver. Veja o Relógio da Chuva, acompanhe o radar ao vivo e receba um aviso antes de a chuva chegar.",
    h1="O ESSENCIAL, NUM PISCAR DE OLHOS",
    b1="Relógio da Chuva: as próximas 2 horas num mostrador. Quando começa, com que força e quando para",
    b2="Chuva, neve, vento e qualidade do ar numa única tela limpa",
    b3="Previsão por hora e de 14 dias para qualquer cidade do mundo",
    h2="RADAR AO VIVO",
    b4="Cores de chuva fortes num mapa escuro, em todo o planeta",
    b5="Animação da previsão de chuva até 48 horas",
    b6="Camadas de nuvens, vento, temperatura e pressão",
    b7="Fluxo de vento animado",
    h3="ALERTAS QUE IMPORTAM",
    b8="Alertas de chuva para sua localização e lugares salvos",
    b9="Rastreador de ciclones com trajetórias, cones de previsão e alertas",
    h4="PRIVACIDADE EM PRIMEIRO LUGAR",
    b10="Sem conta, sem anúncios, sem rastreamento",
    b11="Bloqueio opcional com Face ID",
    b12="A IA roda no seu iPhone",
    h5="PLANOS",
    plans="O RainPulse é gratuito. Essential e Pro liberam o gráfico de chuva minuto a minuto, previsões mais longas, alertas para até 20 lugares, camadas extras no mapa e dicas com IA. As assinaturas renovam automaticamente, a menos que sejam canceladas pelo menos 24 horas antes do fim do período. Gerencie ou cancele nos ajustes da sua conta Apple.",
    data="Dados meteorológicos", terms="Termos de uso", privacy="Política de privacidade",
)

DE = dict(
    hook="Wisse genau, wann es regnet.",
    intro="RainPulse zeigt dir minutengenau, wann der Regen beginnt und aufhört, egal wo du bist. Ein Blick auf die Regenuhr, das Live-Radar und eine Warnung, bevor der Regen dich erreicht.",
    h1="DAS WICHTIGSTE AUF EINEN BLICK",
    b1="Regenuhr: die nächsten 2 Stunden als Zifferblatt. Wann es losgeht, wie stark und wann es aufhört",
    b2="Regen, Schnee, Wind und Luftqualität auf einem aufgeräumten Bildschirm",
    b3="Stündliche und 14-Tage-Vorhersage für jede Stadt der Welt",
    h2="LIVE-REGENRADAR",
    b4="Kräftige Regenfarben auf dunkler Karte, weltweit",
    b5="Animierte Regenvorhersage bis zu 48 Stunden",
    b6="Ebenen für Wolken, Wind, Temperatur und Luftdruck",
    b7="Animierte Windströmung",
    h3="WARNUNGEN, DIE ZÄHLEN",
    b8="Regenwarnungen für deinen Standort und gespeicherte Orte",
    b9="Zyklon-Tracker mit Zugbahnen, Prognosekegeln und Warnungen",
    h4="DATENSCHUTZ AB WERK",
    b10="Kein Konto, keine Werbung, kein Tracking",
    b11="Optionale Sperre mit Face ID",
    b12="KI-Tipps laufen direkt auf deinem iPhone",
    h5="ABOS",
    plans="RainPulse ist kostenlos. Essential und Pro schalten das minutengenaue Regendiagramm, längere Vorhersagen, Warnungen für bis zu 20 Orte, zusätzliche Kartenebenen und KI-Tipps frei. Abos verlängern sich automatisch, sofern sie nicht mindestens 24 Stunden vor Ablauf gekündigt werden. Verwalten oder kündigen in den Einstellungen deines Apple Accounts.",
    data="Wetterdaten", terms="Nutzungsbedingungen", privacy="Datenschutzerklärung",
)

FR = dict(
    hook="Sachez exactement quand il va pleuvoir.",
    intro="RainPulse vous montre quand la pluie commence et s'arrête, minute par minute, où que vous soyez. Un coup d'œil à l'Horloge de pluie, le radar en direct, et une alerte avant que la pluie n'arrive.",
    h1="L'ESSENTIEL EN UN COUP D'ŒIL",
    b1="Horloge de pluie : les 2 prochaines heures sur un cadran. Quand ça commence, avec quelle intensité et quand ça s'arrête",
    b2="Pluie, neige, vent et qualité de l'air sur un seul écran épuré",
    b3="Prévisions heure par heure et sur 14 jours pour toutes les villes du monde",
    h2="RADAR EN DIRECT",
    b4="Des couleurs de pluie vives sur une carte sombre, partout sur Terre",
    b5="Animation des prévisions de pluie jusqu'à 48 heures",
    b6="Calques nuages, vent, température et pression",
    b7="Flux de vent animé",
    h3="DES ALERTES UTILES",
    b8="Alertes pluie pour votre position et vos lieux enregistrés",
    b9="Suivi des cyclones avec trajectoires, cônes de prévision et alertes",
    h4="CONFIDENTIEL PAR NATURE",
    b10="Pas de compte, pas de pub, pas de pistage",
    b11="Verrouillage Face ID en option",
    b12="L'IA fonctionne sur votre iPhone",
    h5="ABONNEMENTS",
    plans="RainPulse est gratuit. Essential et Pro débloquent le graphique de pluie minute par minute, des prévisions plus longues, des alertes pour 20 lieux, des calques supplémentaires et des conseils IA. Les abonnements se renouvellent automatiquement sauf annulation au moins 24 heures avant la fin de la période. Gérez ou annulez dans les réglages de votre compte Apple.",
    data="Données météo", terms="Conditions d'utilisation", privacy="Politique de confidentialité",
)

HI = dict(
    hook="जानिए ठीक कब बारिश होगी।",
    intro="RainPulse आपको मिनट-दर-मिनट बताता है कि बारिश कब शुरू होगी और कब रुकेगी, आप जहाँ भी हों। रेन क्लॉक देखें, लाइव रडार चेक करें और बारिश पहुँचने से पहले अलर्ट पाएँ।",
    h1="ज़रूरी जानकारी, एक नज़र में",
    b1="रेन क्लॉक: अगले 2 घंटे एक डायल पर। बारिश कब शुरू होगी, कितनी तेज़ और कब रुकेगी",
    b2="बारिश, बर्फ़, हवा और वायु गुणवत्ता एक साफ़ स्क्रीन पर",
    b3="दुनिया के हर शहर के लिए घंटेवार और 14 दिन का पूर्वानुमान",
    h2="लाइव रडार",
    b4="गहरे नक्शे पर बारिश के चमकीले रंग, पूरी दुनिया में",
    b5="48 घंटे तक बारिश के पूर्वानुमान का एनिमेशन",
    b6="बादल, हवा, तापमान और वायुदाब की परतें",
    b7="हवा का एनिमेटेड प्रवाह",
    h3="काम के अलर्ट",
    b8="आपकी लोकेशन और सेव की गई जगहों के लिए बारिश अलर्ट",
    b9="चक्रवात ट्रैकर: रास्ता, पूर्वानुमान कोन और अलर्ट",
    h4="निजता सबसे पहले",
    b10="कोई अकाउंट नहीं, कोई विज्ञापन नहीं, कोई ट्रैकिंग नहीं",
    b11="वैकल्पिक Face ID लॉक",
    b12="AI सुझाव आपके iPhone पर ही चलते हैं",
    h5="प्लान",
    plans="RainPulse मुफ़्त है। Essential और Pro से मिनट-दर-मिनट बारिश चार्ट, लंबा पूर्वानुमान, 20 जगहों तक अलर्ट, अतिरिक्त मैप परतें और AI सुझाव मिलते हैं। सदस्यता अपने आप रिन्यू होती है, जब तक अवधि खत्म होने से कम से कम 24 घंटे पहले रद्द न की जाए। अपने Apple अकाउंट सेटिंग्स में प्रबंधित या रद्द करें।",
    data="मौसम डेटा", terms="उपयोग की शर्तें", privacy="गोपनीयता नीति",
)

ID = dict(
    hook="Tahu persis kapan hujan turun.",
    intro="RainPulse menunjukkan kapan hujan mulai dan berhenti, menit demi menit, di mana pun Anda berada. Lihat Jam Hujan, cek radar langsung, dan dapatkan peringatan sebelum hujan tiba.",
    h1="YANG PENTING, SEKALI LIHAT",
    b1="Jam Hujan: 2 jam ke depan dalam satu dial. Kapan mulai, seberapa deras, dan kapan berhenti",
    b2="Hujan, salju, angin, dan kualitas udara dalam satu layar yang rapi",
    b3="Prakiraan per jam dan 14 hari untuk setiap kota di dunia",
    h2="RADAR LANGSUNG",
    b4="Warna hujan yang tegas di peta gelap, di seluruh dunia",
    b5="Animasi prakiraan hujan hingga 48 jam",
    b6="Lapisan awan, angin, suhu, dan tekanan udara",
    b7="Aliran angin animasi",
    h3="PERINGATAN YANG PENTING",
    b8="Peringatan hujan untuk lokasi Anda dan tempat tersimpan",
    b9="Pelacak siklon dengan lintasan badai, kerucut prakiraan, dan peringatan",
    h4="PRIVASI SEJAK AWAL",
    b10="Tanpa akun, tanpa iklan, tanpa pelacakan",
    b11="Kunci Face ID opsional",
    b12="Wawasan AI berjalan di iPhone Anda",
    h5="PAKET",
    plans="RainPulse gratis digunakan. Essential dan Pro membuka grafik hujan menit demi menit, prakiraan lebih panjang, peringatan untuk hingga 20 tempat, lapisan peta tambahan, dan wawasan AI. Langganan diperpanjang otomatis kecuali dibatalkan setidaknya 24 jam sebelum periode berakhir. Kelola atau batalkan di pengaturan Akun Apple Anda.",
    data="Data cuaca", terms="Ketentuan Penggunaan", privacy="Kebijakan Privasi",
)

JA = dict(
    hook="雨が降るタイミングが、正確にわかる。",
    intro="RainPulse は、雨が降り始める時刻と止む時刻を1分単位でお知らせします。レインクロックをひと目見て、ライブ雨雲レーダーを確認し、雨が来る前に通知を受け取れます。",
    h1="大事な情報をひと目で",
    b1="レインクロック：この先2時間を文字盤で表示。降り始め・強さ・止む時刻がすぐわかる",
    b2="雨・雪・風・大気質をすっきりした1画面に",
    b3="世界中の都市の1時間ごと・14日間の天気予報",
    h2="ライブ雨雲レーダー",
    b4="ダークマップに鮮やかな雨の色、世界中どこでも",
    b5="最大48時間先までの降水予報アニメーション",
    b6="雲・風・気温・気圧のレイヤー",
    b7="風の流れのアニメーション",
    h3="本当に役立つ通知",
    b8="現在地と保存した場所の雨通知",
    b9="台風・サイクロンの進路、予報円、通知",
    h4="プライバシー重視の設計",
    b10="アカウント不要・広告なし・トラッキングなし",
    b11="Face ID ロック（任意）",
    b12="AI インサイトは iPhone 上で動作",
    h5="プラン",
    plans="RainPulse は無料でお使いいただけます。Essential と Pro では1分単位の降水グラフ、長期予報、最大20か所の通知、追加の地図レイヤー、AI インサイトが利用できます。サブスクリプションは期間終了の24時間前までに解約しない限り自動更新されます。Apple アカウントの設定からいつでも管理・解約できます。",
    data="気象データ", terms="利用規約", privacy="プライバシーポリシー",
)

AR = dict(
    hook="اعرف بالضبط متى سيهطل المطر.",
    intro="يعرض لك RainPulse متى يبدأ المطر ومتى يتوقف، دقيقة بدقيقة، أينما كنت. ألقِ نظرة على ساعة المطر، وتابع الرادار المباشر، واحصل على تنبيه قبل وصول المطر.",
    h1="الأساسيات بنظرة واحدة",
    b1="ساعة المطر: الساعتان القادمتان على قرص واحد. متى يبدأ المطر وما شدته ومتى يتوقف",
    b2="المطر والثلج والرياح وجودة الهواء في شاشة واحدة أنيقة",
    b3="توقعات كل ساعة ولمدة 14 يومًا لكل مدن العالم",
    h2="رادار مباشر",
    b4="ألوان مطر واضحة على خريطة داكنة، في أي مكان على الأرض",
    b5="رسوم متحركة لتوقعات المطر حتى 48 ساعة",
    b6="طبقات للسحب والرياح والحرارة والضغط الجوي",
    b7="حركة رياح متحركة",
    h3="تنبيهات مهمة",
    b8="تنبيهات المطر لموقعك والأماكن المحفوظة",
    b9="متتبع الأعاصير مع المسارات ومخروط التوقعات والتنبيهات",
    h4="الخصوصية أولًا",
    b10="بلا حساب، بلا إعلانات، بلا تتبع",
    b11="قفل اختياري بـ Face ID",
    b12="رؤى الذكاء الاصطناعي تعمل على جهاز iPhone الخاص بك",
    h5="الخطط",
    plans="استخدام RainPulse مجاني. تفتح خطتا Essential وPro مخطط المطر دقيقة بدقيقة وتوقعات أطول وتنبيهات حتى 20 مكانًا وطبقات خرائط إضافية ورؤى بالذكاء الاصطناعي. تتجدد الاشتراكات تلقائيًا ما لم تُلغَ قبل 24 ساعة على الأقل من نهاية الفترة. يمكنك الإدارة أو الإلغاء من إعدادات حساب Apple.",
    data="بيانات الطقس", terms="شروط الاستخدام", privacy="سياسة الخصوصية",
)

TA = dict(
    hook="மழை எப்போது பெய்யும் என்று துல்லியமாக அறியுங்கள்.",
    intro="நீங்கள் எங்கிருந்தாலும், மழை எப்போது தொடங்கும், எப்போது நிற்கும் என்பதை RainPulse நிமிடத்துக்கு நிமிடம் காட்டுகிறது. மழைக் கடிகாரத்தைப் பாருங்கள், நேரடி ரேடாரைச் சரிபாருங்கள், மழை வருவதற்கு முன் எச்சரிக்கை பெறுங்கள்.",
    h1="முக்கியமானவை, ஒரே பார்வையில்",
    b1="மழைக் கடிகாரம்: அடுத்த 2 மணி நேரம் ஒரு டயலில். மழை எப்போது தொடங்கும், எவ்வளவு வலுவாக, எப்போது நிற்கும்",
    b2="மழை, பனி, காற்று, காற்றின் தரம் ஒரே தெளிவான திரையில்",
    b3="உலகின் ஒவ்வொரு நகரத்துக்கும் மணிநேர மற்றும் 14 நாள் முன்னறிவிப்பு",
    h2="நேரடி ரேடார்",
    b4="இருண்ட வரைபடத்தில் தெளிவான மழை நிறங்கள், உலகம் முழுவதும்",
    b5="48 மணி நேரம் வரை மழை முன்னறிவிப்பு அனிமேஷன்",
    b6="மேகம், காற்று, வெப்பநிலை, காற்றழுத்த அடுக்குகள்",
    b7="அனிமேஷன் காற்றோட்டம்",
    h3="பயனுள்ள எச்சரிக்கைகள்",
    b8="உங்கள் இருப்பிடம் மற்றும் சேமித்த இடங்களுக்கு மழை எச்சரிக்கைகள்",
    b9="புயல் கண்காணிப்பு: பாதை, முன்னறிவிப்பு கூம்பு, எச்சரிக்கைகள்",
    h4="தனியுரிமை முதலில்",
    b10="கணக்கு இல்லை, விளம்பரம் இல்லை, கண்காணிப்பு இல்லை",
    b11="விருப்பத்தேர்வு Face ID பூட்டு",
    b12="AI பரிந்துரைகள் உங்கள் iPhone-இலேயே இயங்கும்",
    h5="திட்டங்கள்",
    plans="RainPulse இலவசம். Essential மற்றும் Pro மூலம் நிமிடத்துக்கு நிமிடம் மழை வரைபடம், நீண்ட முன்னறிவிப்பு, 20 இடங்கள் வரை எச்சரிக்கைகள், கூடுதல் வரைபட அடுக்குகள், AI பரிந்துரைகள் கிடைக்கும். காலம் முடிவதற்கு குறைந்தது 24 மணி நேரத்துக்கு முன் ரத்து செய்யாவிட்டால் சந்தா தானாகப் புதுப்பிக்கப்படும். உங்கள் Apple கணக்கு அமைப்புகளில் நிர்வகிக்கலாம் அல்லது ரத்து செய்யலாம்.",
    data="வானிலைத் தரவு", terms="பயன்பாட்டு விதிமுறைகள்", privacy="தனியுரிமைக் கொள்கை",
)

VI = dict(
    hook="Biết chính xác khi nào trời mưa.",
    intro="RainPulse cho bạn biết khi nào mưa bắt đầu và tạnh, từng phút một, dù bạn ở đâu. Nhìn Đồng hồ Mưa, xem radar trực tiếp và nhận cảnh báo trước khi mưa đến.",
    h1="ĐIỀU QUAN TRỌNG, CHỈ MỘT CÁI NHÌN",
    b1="Đồng hồ Mưa: 2 giờ tới trên một mặt đồng hồ. Khi nào mưa, mưa to cỡ nào và khi nào tạnh",
    b2="Mưa, tuyết, gió và chất lượng không khí trên một màn hình gọn gàng",
    b3="Dự báo theo giờ và 14 ngày cho mọi thành phố trên thế giới",
    h2="RADAR TRỰC TIẾP",
    b4="Màu mưa rõ nét trên bản đồ tối, khắp thế giới",
    b5="Hoạt ảnh dự báo mưa đến 48 giờ",
    b6="Các lớp mây, gió, nhiệt độ và áp suất",
    b7="Dòng gió chuyển động",
    h3="CẢNH BÁO HỮU ÍCH",
    b8="Cảnh báo mưa cho vị trí của bạn và các địa điểm đã lưu",
    b9="Theo dõi bão với đường đi, nón dự báo và cảnh báo",
    h4="RIÊNG TƯ NGAY TỪ ĐẦU",
    b10="Không tài khoản, không quảng cáo, không theo dõi",
    b11="Khóa Face ID tùy chọn",
    b12="Gợi ý AI chạy ngay trên iPhone của bạn",
    h5="GÓI DỊCH VỤ",
    plans="RainPulse miễn phí. Essential và Pro mở khóa biểu đồ mưa từng phút, dự báo dài hơn, cảnh báo cho tối đa 20 địa điểm, thêm lớp bản đồ và gợi ý AI. Gói đăng ký tự động gia hạn trừ khi bị hủy ít nhất 24 giờ trước khi kết thúc kỳ. Quản lý hoặc hủy trong cài đặt Tài khoản Apple.",
    data="Dữ liệu thời tiết", terms="Điều khoản sử dụng", privacy="Chính sách quyền riêng tư",
)

# name ≤30, subtitle ≤30, keywords ≤100 (comma-separated, no words already in name/subtitle)
LISTINGS = {
    "en-US": dict(name="RainPulse: Live Rain Radar", subtitle="Rain alerts, cyclones & AQI",
                  keywords="weather,forecast,storm,thunderstorm,precipitation,nowcast,minute,hourly,map,wind,snow,hurricane",
                  promo="Know exactly when it rains. The Rain Clock shows the next 2 hours at a glance, with live radar, cyclone tracking, wind and air quality.",
                  t=EN),
    "en-GB": dict(name="RainPulse: Live Rain Radar", subtitle="Rain alerts, storms & air",
                  keywords="weather,forecast,showers,drizzle,precipitation,met,map,wind,snow,pollution,typhoon,flood,cyclone",
                  promo="Know exactly when it rains. The Rain Clock shows the next 2 hours at a glance, with live radar, storm tracking, wind and air quality.",
                  t=EN),
    "en-AU": dict(name="RainPulse: Live Rain Radar", subtitle="Rain alerts, cyclones & wind",
                  keywords="weather,forecast,bom,storm,showers,precipitation,map,snow,air,quality,bushfire,smoke,uv",
                  promo="Know exactly when it rains. The Rain Clock shows the next 2 hours at a glance, with live radar, cyclone tracking, wind and air quality.",
                  t=EN),
    "es-ES": dict(name="RainPulse: Radar de Lluvia", subtitle="Alertas de lluvia y tormentas",
                  keywords="tiempo,clima,pronóstico,previsión,precipitación,mapa,viento,nieve,aire,ciclón,huracán,chubascos",
                  promo="Sabe exactamente cuándo llueve. El Reloj de Lluvia muestra las próximas 2 horas de un vistazo, con radar en vivo, ciclones, viento y calidad del aire.",
                  t=ES),
    "es-MX": dict(name="RainPulse: Radar de Lluvia", subtitle="Alertas de lluvia y huracanes",
                  keywords="clima,tiempo,pronóstico,precipitación,mapa,viento,nieve,aire,ciclón,tormenta,calidad,smog",
                  promo="Sabe exactamente cuándo llueve. El Reloj de Lluvia muestra las próximas 2 horas de un vistazo, con radar en vivo, huracanes, viento y calidad del aire.",
                  t=ES),
    "pt-BR": dict(name="RainPulse: Radar de Chuva", subtitle="Alertas de chuva e tempestades",
                  keywords="tempo,clima,previsão,precipitação,mapa,vento,neve,ar,qualidade,ciclone,temporal,chuvas",
                  promo="Saiba exatamente quando vai chover. O Relógio da Chuva mostra as próximas 2 horas num relance, com radar ao vivo, ciclones, vento e qualidade do ar.",
                  t=PT),
    "de-DE": dict(name="RainPulse: Live Regenradar", subtitle="Regenwarnung, Unwetter & Wind",
                  keywords="wetter,vorhersage,niederschlag,gewitter,sturm,karte,schnee,luftqualität,zyklon,regen,radar",
                  promo="Wisse genau, wann es regnet. Die Regenuhr zeigt die nächsten 2 Stunden auf einen Blick, mit Live-Radar, Zyklonen, Wind und Luftqualität.",
                  t=DE),
    "fr-FR": dict(name="RainPulse : Radar de Pluie", subtitle="Alertes pluie, orages et vent",
                  keywords="météo,prévisions,précipitations,carte,neige,qualité,air,cyclone,tempête,averse,radar,temps",
                  promo="Sachez exactement quand il pleut. L'Horloge de pluie montre les 2 prochaines heures d'un coup d'œil, avec radar en direct, cyclones, vent et qualité de l'air.",
                  t=FR),
    "hi": dict(name="RainPulse: बारिश रडार", subtitle="बारिश अलर्ट, चक्रवात और AQI",
               keywords="मौसम,बारिश,पूर्वानुमान,मानसून,तूफ़ान,हवा,प्रदूषण,नक्शा,weather,rain,radar,monsoon,cyclone",
               promo="जानिए ठीक कब बारिश होगी। रेन क्लॉक अगले 2 घंटे एक नज़र में दिखाता है, साथ में लाइव रडार, चक्रवात, हवा और वायु गुणवत्ता।",
               t=HI),
    "id": dict(name="RainPulse: Radar Hujan", subtitle="Peringatan hujan & badai",
               keywords="cuaca,prakiraan,hujan,radar,angin,salju,udara,kualitas,siklon,petir,peta,banjir,bmkg",
               promo="Tahu persis kapan hujan. Jam Hujan menampilkan 2 jam ke depan sekilas, dengan radar langsung, siklon, angin, dan kualitas udara.",
               t=ID),
    "ja": dict(name="RainPulse: 雨雲レーダー", subtitle="雨の通知・台風・大気質",
               keywords="天気,天気予報,雨,降水,ゲリラ豪雨,雷,台風,風,雪,地図,気象,ナウキャスト,大気汚染,PM2.5",
               promo="雨が降るタイミングが正確にわかる。レインクロックでこの先2時間をひと目で。ライブレーダー、台風、風、大気質も。",
               t=JA),
    "ar-SA": dict(name="RainPulse: رادار المطر", subtitle="تنبيهات المطر والعواصف",
                  keywords="طقس,توقعات,مطر,رادار,رياح,غبار,جودة,الهواء,إعصار,عاصفة,خريطة,أمطار,ثلج",
                  promo="اعرف بالضبط متى يهطل المطر. ساعة المطر تعرض الساعتين القادمتين بنظرة، مع رادار مباشر وأعاصير ورياح وجودة الهواء.",
                  t=AR),
    "ta-IN": dict(name="RainPulse: மழை ரேடார்", subtitle="மழை எச்சரிக்கை, புயல், AQI",
               keywords="வானிலை,மழை,முன்னறிவிப்பு,புயல்,காற்று,பருவமழை,வரைபடம்,weather,rain,radar,chennai",
               promo="மழை எப்போது பெய்யும் என்று துல்லியமாக அறியுங்கள். மழைக் கடிகாரம் அடுத்த 2 மணி நேரத்தை ஒரே பார்வையில் காட்டுகிறது.",
               t=TA),
    "vi": dict(name="RainPulse: Radar Mưa", subtitle="Cảnh báo mưa, bão và AQI",
               keywords="thời tiết,dự báo,mưa,radar,bão,gió,không khí,bản đồ,giông,lũ,tuyết,nồm",
               promo="Biết chính xác khi nào trời mưa. Đồng hồ Mưa cho thấy 2 giờ tới trong một cái nhìn, kèm radar trực tiếp, bão, gió và chất lượng không khí.",
               t=VI),
}

if __name__ == "__main__":
    for loc, d in LISTINGS.items():
        kw = d["keywords"]
        print(f"{loc:6} name={len(d['name'])} sub={len(d['subtitle'])} kw={len(kw)} kwbytes={len(kw.encode())} promo={len(d['promo'])} desc={len(desc(d['t']))}")
        assert len(d["name"]) <= 30 and len(d["subtitle"]) <= 30 and len(kw) <= 100 and len(d["promo"]) <= 170, loc
