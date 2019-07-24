package Serge::Util::LangID;

use strict;

our %alias = (
  'ar' => 'ar-ae',
  'zh' => 'zh-cn',
  'en' => 'en-us',
  'fr' => 'fr-fr',
  'de' => 'de-de',
  'it' => 'it-it',
  'br' => 'pt-br',
  'pt' => 'pt-pt',
  'nl' => 'nl-nl',
  'no' => 'nn',
  'sr' => 'sr-cyrl',
  'sh' => 'sr-latn',
  'es' => 'es-es',
  'sw' => 'sw-ke',
  'ur' => 'ur-pk',
  'uz' => 'uz-cyrl',
);

# Locale mappings were taken from Win32::Locale
# (Copyright (c) 2001,2003 Sean M. Burke. All rights reserved.)
# and reversed to get the locale id by lang tag

# lang/sublang constants were taken from
# http://msdn.microsoft.com/en-us/library/dd318693(v=VS.85).aspx

# codepage identifiers were taken from
# http://msdn.microsoft.com/en-us/library/dd317756(v=VS.85).aspx
# (need to be verified and defined for more locales)

our $default_codepage = 1252; # ANSI Latin 1; Western European (Windows)

our %map = (
  ''        => {code => 0x0000, lang => 'LANG_NEUTRAL', sublang => 'SUBLANG_NEUTRAL', afx => 'AFX_TARG_ENU', cp => $default_codepage},  # reasonable defaults

  'af'      => {code => 0x0436, lang => 'LANG_AFRIKAANS', sublang => 'SUBLANG_AFRIKAANS_SOUTH_AFRICA', afx => 'AFX_TARG_AFK'},  # <AFK> <Afrikaans> <Afrikaans>
  'sq'      => {code => 0x041c, lang => 'LANG_ALBANIAN', sublang => 'SUBLANG_ALBANIAN_ALBANIA', afx => 'AFX_TARG_SQI'},  # <SQI> <Albanian> <Albanian>

  'ar-sa'   => {code => 0x0401, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_SAUDI_ARABIA', afx => 'AFX_TARG_ARA', cp => 1256},  # <ARA> <Arabic> <Arabic (Saudi Arabia)>
  'ar-iq'   => {code => 0x0801, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_IRAQ', afx => 'AFX_TARG_ARI', cp => 1256},  # <ARI> <Arabic> <Arabic (Iraq)>
  'ar-eg'   => {code => 0x0C01, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_EGYPT', afx => 'AFX_TARG_ARE', cp => 1256},  # <ARE> <Arabic> <Arabic (Egypt)>
  'ar-ly'   => {code => 0x1001, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_LIBYA', afx => 'AFX_TARG_ARL', cp => 1256},  # <ARL> <Arabic> <Arabic (Libya)>
  'ar-dz'   => {code => 0x1401, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_ALGERIA', afx => 'AFX_TARG_ARG', cp => 1256},  # <ARG> <Arabic> <Arabic (Algeria)>
  'ar-ma'   => {code => 0x1801, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_MOROCCO', afx => 'AFX_TARG_ARM', cp => 1256},  # <ARM> <Arabic> <Arabic (Morocco)>
  'ar-tn'   => {code => 0x1C01, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_TUNISIA', afx => 'AFX_TARG_ART', cp => 1256},  # <ART> <Arabic> <Arabic (Tunisia)>
  'ar-om'   => {code => 0x2001, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_OMAN', afx => 'AFX_TARG_ARO', cp => 1256},  # <ARO> <Arabic> <Arabic (Oman)>
  'ar-ye'   => {code => 0x2401, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_YEMEN', afx => 'AFX_TARG_ARY', cp => 1256},  # <ARY> <Arabic> <Arabic (Yemen)>
  'ar-sy'   => {code => 0x2801, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_SYRIA', afx => 'AFX_TARG_ARS', cp => 1256},  # <ARS> <Arabic> <Arabic (Syria)>
  'ar-jo'   => {code => 0x2C01, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_JORDAN', afx => 'AFX_TARG_ARJ', cp => 1256},  # <ARJ> <Arabic> <Arabic (Jordan)>
  'ar-lb'   => {code => 0x3001, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_LEBANON', afx => 'AFX_TARG_ARB', cp => 1256},  # <ARB> <Arabic> <Arabic (Lebanon)>
  'ar-kw'   => {code => 0x3401, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_KUWAIT', afx => 'AFX_TARG_ARK', cp => 1256},  # <ARK> <Arabic> <Arabic (Kuwait)>
  'ar-ae'   => {code => 0x3801, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_UAE', afx => 'AFX_TARG_ARU', cp => 1256},  # <ARU> <Arabic> <Arabic (U.A.E.)>
  'ar-bh'   => {code => 0x3C01, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_BAHRAIN', afx => 'AFX_TARG_ARH', cp => 1256},  # <ARH> <Arabic> <Arabic (Bahrain)>
  'ar-qa'   => {code => 0x4001, lang => 'LANG_ARABIC', sublang => 'SUBLANG_ARABIC_QATAR', afx => 'AFX_TARG_ARQ', cp => 1256},  # <ARQ> <Arabic> <Arabic (Qatar)>

  'hy'      => {code => 0x042b, lang => 'LANG_ARMENIAN', sublang => 'SUBLANG_ARMENIAN_ARMENIA', afx => 'AFX_TARG_HYE'},  # <HYE> <Armenian> <Armenian>
  'as'      => {code => 0x044d, lang => 'LANG_ASSAMESE', sublang => 'SUBLANG_ASSAMESE_INDIA', afx => 'AFX_TARG_ASM'},  # <ASM> <Assamese> <Assamese>
  'az-latn' => {code => 0x042c, lang => 'LANG_AZERI', sublang => 'SUBLANG_AZERI_LATIN', afx => 'AFX_TARG_AZE'},  # <AZE> <Azeri> <Azeri (Latin)>
  'az-cyrl' => {code => 0x082c, lang => 'LANG_AZERI', sublang => 'SUBLANG_AZERI_CYRILLIC', afx => 'AFX_TARG_AZC'},  # <AZC> <Azeri> <Azeri (Cyrillic)>
  'eu'      => {code => 0x042D, lang => 'LANG_BASQUE', sublang => 'SUBLANG_BASQUE_BASQUE', afx => 'AFX_TARG_EUQ'},  # <EUQ> <Basque> <Basque>
  'be'      => {code => 0x0423, lang => 'LANG_BELARUSIAN', sublang => 'SUBLANG_BELARUSIAN_BELARUS', afx => 'AFX_TARG_BEL'},  # <BEL> <Belarussian> <Belarussian>
  'bn'      => {code => 0x0445, lang => 'LANG_BENGALI', sublang => 'SUBLANG_BENGALI_BANGLADESH', afx => 'AFX_TARG_BEN'},  # <BEN> <Bengali> <Bengali>
  'bg'      => {code => 0x0402, lang => 'LANG_BULGARIAN', sublang => 'SUBLANG_BULGARIAN_BULGARIA', afx => 'AFX_TARG_BGR'},  # <BGR> <Bulgarian> <Bulgarian>
  'ca'      => {code => 0x0403, lang => 'LANG_CATALAN', sublang => 'SUBLANG_CATALAN_CATALAN', afx => 'AFX_TARG_CAT'},  # <CAT> <Catalan> <Catalan>

  # Chinese is zh, not cn!
  'zh-tw'   => {code => 0x0404, lang => 'LANG_CHINESE', sublang => 'SUBLANG_CHINESE_TRADITIONAL'},  # 7C04 code <CHT> <Chinese> <Chinese (Taiwan)>
  'zh-cn'   => {code => 0x0804, lang => 'LANG_CHINESE', sublang => 'SUBLANG_CHINESE_SIMPLIFIED'},  # 0004 code <> <Chinese> <Chinese (PRC)>
  'zh-hk'   => {code => 0x0C04, lang => 'LANG_CHINESE', sublang => 'SUBLANG_CHINESE_HONGKONG', afx => 'AFX_TARG_ZHH'},  # <ZHH> <Chinese> <Chinese (Hong Kong)>
  'zh-sg'   => {code => 0x1004, lang => 'LANG_CHINESE', sublang => 'SUBLANG_CHINESE_SINGAPORE', afx => 'AFX_TARG_ZHI'},  # <ZHI> <Chinese> <Chinese (Singapore)>
  'zh-mo'   => {code => 0x1404, lang => 'LANG_CHINESE', sublang => 'SUBLANG_CHINESE_MACAU', afx => 'AFX_TARG_ZHM'},  # <ZHM> <Chinese> <Chinese (Macau SAR)>

  'hr'      => {code => 0x041a, lang => 'LANG_CROATIAN', sublang => 'SUBLANG_CROATIAN_CROATIA', afx => 'AFX_TARG_HRV'},  # <HRV> <Croatian> <Croatian>
  'cs'      => {code => 0x0405, lang => 'LANG_CZECH', sublang => 'SUBLANG_CZECH_CZECH_REPUBLIC', afx => 'AFX_TARG_CSY', cp => 1250},  # <CSY> <Czech> <Czech>
  'da'      => {code => 0x0406, lang => 'LANG_DANISH', sublang => 'SUBLANG_DANISH_DENMARK', afx => 'AFX_TARG_DAN'},  # <DAN> <Danish> <Danish>
  'nl-nl'   => {code => 0x0413, lang => 'LANG_DUTCH', sublang => 'SUBLANG_DUTCH', afx => 'AFX_TARG_NLD'},  # <NLD> <Dutch> <Dutch (Netherlands)>
  'nl-be'   => {code => 0x0813, lang => 'LANG_DUTCH', sublang => 'SUBLANG_DUTCH_BELGIAN', afx => 'AFX_TARG_NLB'},  # <NLB> <Dutch> <Dutch (Belgium)>

  'en-us'   => {code => 0x0409, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_US', afx => 'AFX_TARG_ENU'},  # <ENU> <English> <English (United States)>
  'en-gb'   => {code => 0x0809, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_UK', afx => 'AFX_TARG_ENG'},  # <ENG> <English> <English (United Kingdom)>
  'en-au'   => {code => 0x0c09, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_AUS', afx => 'AFX_TARG_ENA'},  # <ENA> <English> <English (Australia)>
  'en-ca'   => {code => 0x1009, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_CAN', afx => 'AFX_TARG_ENC'},  # <ENC> <English> <English (Canada)>
  'en-nz'   => {code => 0x1409, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_NZ', afx => 'AFX_TARG_ENZ'},  # <ENZ> <English> <English (New Zealand)>
  'en-ie'   => {code => 0x1809, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_IRELAND', afx => 'AFX_TARG_ENI'},  # <ENI> <English> <English (Ireland)>
  'en-za'   => {code => 0x1c09, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_SOUTH_AFRICA', afx => 'AFX_TARG_ENS'},  # <ENS> <English> <English (South Africa)>
  'en-jm'   => {code => 0x2009, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_JAMAICA', afx => 'AFX_TARG_ENJ'},  # <ENJ> <English> <English (Jamaica)>
  'en-jm'   => {code => 0x2409, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_CARIBBEAN', afx => 'AFX_TARG_ENB'},  # <ENB> <English> <English (Caribbean)>  # a hack
  'en-bz'   => {code => 0x2809, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_BELIZE', afx => 'AFX_TARG_ENL'},  # <ENL> <English> <English (Belize)>
  'en-tt'   => {code => 0x2c09, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_TRINIDAD', afx => 'AFX_TARG_ENT'},  # <ENT> <English> <English (Trinidad)>
  'en-zw'   => {code => 0x3009, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_ZIMBABWE', afx => 'AFX_TARG_ENW'},  # <ENW> <English> <English (Zimbabwe)>
  'en-ph'   => {code => 0x3409, lang => 'LANG_ENGLISH', sublang => 'SUBLANG_ENGLISH_PHILIPPINES', afx => 'AFX_TARG_ENP'},  # <ENP> <English> <English (Philippines)>

  'et'      => {code => 0x0425, lang => 'LANG_ESTONIAN', sublang => 'SUBLANG_ESTONIAN_ESTONIA', afx => 'AFX_TARG_ETI'},  # <ETI> <Estonian> <Estonian>
  'fo'      => {code => 0x0438, lang => 'LANG_FAEROESE', sublang => 'SUBLANG_FAEROESE_FAROE_ISLANDS', afx => 'AFX_TARG_FOS'},  # <FOS> <Faeroese> <Faeroese>
  'fa'      => {code => 0x0429, lang => 'LANG_PERSIAN', sublang => 'SUBLANG_PERSIAN_IRAN'},  # <FAR> <Farsi> <Farsi>   # = Persian
  'fi'      => {code => 0x040b, lang => 'LANG_FINNISH', sublang => 'SUBLANG_FINNISH_FINLAND', afx => 'AFX_TARG_FIN'},  # <FIN> <Finnish> <Finnish>

  'fr-fr'   => {code => 0x040c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH', afx => 'AFX_TARG_FRA'},  # <FRA> <French> <French (France)>
  'fr-be'   => {code => 0x080c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH_BELGIAN', afx => 'AFX_TARG_FRB'},  # <FRB> <French> <French (Belgium)>
  'fr-ca'   => {code => 0x0c0c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH_CANADIAN', afx => 'AFX_TARG_FRC'},  # <FRC> <French> <French (Canada)>
  'fr-ch'   => {code => 0x100c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH_SWISS', afx => 'AFX_TARG_FRS'},  # <FRS> <French> <French (Switzerland)>
  'fr-lu'   => {code => 0x140c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH_LUXEMBOURG', afx => 'AFX_TARG_FRL'},  # <FRL> <French> <French (Luxembourg)>
  'fr-mc'   => {code => 0x180c, lang => 'LANG_FRENCH', sublang => 'SUBLANG_FRENCH_MONACO', afx => 'AFX_TARG_FRM'},  # <FRM> <French> <French (Monaco)>

  'ka'      => {code => 0x0437, lang => 'LANG_GEORGIAN', sublang => 'SUBLANG_GEORGIAN_GEORGIA', afx => 'AFX_TARG_KAT'},  # <KAT> <Georgian> <Georgian>

  'de-de'   => {code => 0x0407, lang => 'LANG_GERMAN', sublang => 'SUBLANG_GERMAN', afx => 'AFX_TARG_DEU'},  # <DEU> <German> <German (Germany)>
  'de-ch'   => {code => 0x0807, lang => 'LANG_GERMAN', sublang => 'SUBLANG_GERMAN_SWISS', afx => 'AFX_TARG_DES'},  # <DES> <German> <German (Switzerland)>
  'de-at'   => {code => 0x0c07, lang => 'LANG_GERMAN', sublang => 'SUBLANG_GERMAN_AUSTRIAN', afx => 'AFX_TARG_DEA'},  # <DEA> <German> <German (Austria)>
  'de-lu'   => {code => 0x1007, lang => 'LANG_GERMAN', sublang => 'SUBLANG_GERMAN_LUXEMBOURG', afx => 'AFX_TARG_DEL'},  # <DEL> <German> <German (Luxembourg)>
  'de-li'   => {code => 0x1407, lang => 'LANG_GERMAN', sublang => 'SUBLANG_GERMAN_LIECHTENSTEIN', afx => 'AFX_TARG_DEC'},  # <DEC> <German> <German (Liechtenstein)>

  'el'      => {code => 0x0408, lang => 'LANG_GREEK', sublang => 'SUBLANG_GREEK_GREECE', afx => 'AFX_TARG_ELL', cp => 1253},  # <ELL> <Greek> <Greek>
  'gu'      => {code => 0x0447, lang => 'LANG_GUJARATI', sublang => 'SUBLANG_GUJARATI_INDIA', afx => 'AFX_TARG_GUJ'},  # <GUJ> <Gujarati> <Gujarati>
  'he'      => {code => 0x040D, lang => 'LANG_HEBREW', sublang => 'SUBLANG_HEBREW_ISRAEL', afx => 'AFX_TARG_HEB', cp => 1255},  # <HEB> <Hebrew> <Hebrew>  # formerly 'iw'
  'hi'      => {code => 0x0439, lang => 'LANG_HINDI', sublang => 'SUBLANG_HINDI_INDIA', afx => 'AFX_TARG_HIN'},  # <HIN> <Hindi> <Hindi>
  'hu'      => {code => 0x040e, lang => 'LANG_HUNGARIAN', sublang => 'SUBLANG_HUNGARIAN_HUNGARY', afx => 'AFX_TARG_HUN'},  # <HUN> <Hungarian> <Hungarian>
  'is'      => {code => 0x040F, lang => 'LANG_ICELANDIC', sublang => 'SUBLANG_ICELANDIC_ICELAND', afx => 'AFX_TARG_ISL'},  # <ISL> <Icelandic> <Icelandic>
  'id'      => {code => 0x0421, lang => 'LANG_INDONESIAN', sublang => 'SUBLANG_INDONESIAN_INDONESIA', afx => 'AFX_TARG_IND'},  # <IND> <Indonesian> <Indonesian>  # formerly 'in'
  'it-it'   => {code => 0x0410, lang => 'LANG_ITALIAN', sublang => 'SUBLANG_ITALIAN', afx => 'AFX_TARG_ITA'},  # <ITA> <Italian> <Italian (Italy)>
  'it-ch'   => {code => 0x0810, lang => 'LANG_ITALIAN', sublang => 'SUBLANG_ITALIAN_SWISS', afx => 'AFX_TARG_ITS'},  # <ITS> <Italian> <Italian (Switzerland)>
  'ja'      => {code => 0x0411, lang => 'LANG_JAPANESE', sublang => 'SUBLANG_JAPANESE_JAPAN', afx => 'AFX_TARG_JPN', cp => 932},  # <JPN> <Japanese> <Japanese>  # not "jp"!
  'kn'      => {code => 0x044b, lang => 'LANG_KANNADA', sublang => 'SUBLANG_KANNADA_INDIA', afx => 'AFX_TARG_KAN'},  # <KAN> <Kannada> <Kannada>
  'ks'      => {code => 0x0860, lang => 'LANG_KASHMIRI', sublang => 'SUBLANG_KASHMIRI_INDIA', afx => 'AFX_TARG_KAI'},  # <KAI> <Kashmiri> <Kashmiri (India)>
  'kk'      => {code => 0x043f, lang => 'LANG_KAZAK', sublang => 'SUBLANG_KAZAK_KAZAKHSTAN', afx => 'AFX_TARG_KAZ'},  # <KAZ> <Kazakh> <Kazakh>
  'kok'     => {code => 0x0457, lang => 'LANG_KONKANI', sublang => 'SUBLANG_KONKANI_INDIA', afx => 'AFX_TARG_KOK'},  # <KOK> <Konkani> <Konkani>    3-letters!
  'ko'      => {code => 0x0412, lang => 'LANG_KOREAN', sublang => 'SUBLANG_KOREAN', afx => 'AFX_TARG_KOR', cp => 949},  # <KOR> <Korean> <Korean>
  #'ko'      => {code => 0x0812, lang => '', sublang => '', afx => 'AFX_TARG_KOJ'},  # <KOJ> <Korean> <Korean (Johab)>  ?
  'lv'      => {code => 0x0426, lang => 'LANG_LATVIAN', sublang => 'SUBLANG_LATVIAN_LATVIA', afx => 'AFX_TARG_LVI', cp => 1257},  # <LVI> <Latvian> <Latvian>  # = lettish
  'lt'      => {code => 0x0427, lang => 'LANG_LITHUANIAN', sublang => 'SUBLANG_LITHUANIAN_LITHUANIA', afx => 'AFX_TARG_LTH', cp => 1257},  # <LTH> <Lithuanian> <Lithuanian>
  #'lt'      => {code => 0x0827, lang => '', sublang => '', afx => 'AFX_TARG_LTH'},  # <LTH> <Lithuanian> <Lithuanian (Classic)>  ?
  'mk'      => {code => 0x042f, lang => 'LANG_MACEDONIAN', sublang => 'SUBLANG_MACEDONIAN_MACEDONIA', afx => 'AFX_TARG_MKD'},  # <MKD> <FYOR Macedonian> <FYOR Macedonian>
  'ms'      => {code => 0x043e, lang => 'LANG_MALAY', sublang => 'SUBLANG_MALAY_MALAYSIA'},  #  ms-my??? <MSL> <Malay> <Malaysian>
  'ms-bn'   => {code => 0x083e, lang => 'LANG_MALAY', sublang => 'SUBLANG_MALAY_BRUNEI_DARUSSALAM', afx => 'AFX_TARG_MSB'},  # <MSB> <Malay> <Malay Brunei Darussalam>
  'ml'      => {code => 0x044c, lang => 'LANG_MALAYALAM', sublang => 'SUBLANG_MALAYALAM_INDIA', afx => 'AFX_TARG_MAL'},  # <MAL> <Malayalam> <Malayalam>
  'mr'      => {code => 0x044e, lang => 'LANG_MARATHI', sublang => 'SUBLANG_MARATHI_INDIA', afx => 'AFX_TARG_MAR'},  # <MAR> <Marathi> <Marathi>
  'ne-np'   => {code => 0x0461, lang => 'LANG_NEPALI', sublang => 'SUBLANG_NEPALI_NEPAL', afx => 'AFX_TARG_NEP'},  # <NEP> <Nepali> <Nepali (Nepal)>
  'ne-in'   => {code => 0x0861, lang => 'LANG_NEPALI', sublang => 'SUBLANG_NEPALI_INDIA', afx => 'AFX_TARG_NEI'},  # <NEI> <Nepali> <Nepali (India)>
  'nb'      => {code => 0x0414, lang => 'LANG_NORWEGIAN', sublang => 'SUBLANG_NORWEGIAN_BOKMAL', afx => 'AFX_TARG_NOR'},  # <NOR> <Norwegian> <Norwegian (Bokmal)>   #was no-bok
  'nn'      => {code => 0x0814, lang => 'LANG_NORWEGIAN', sublang => 'SUBLANG_NORWEGIAN_NYNORSK', afx => 'AFX_TARG_NON'},  # <NON> <Norwegian> <Norwegian (Nynorsk)>  #was no-nyn
  # note that this leaves nothing using "no" ("Norwegian")
  'or'      => {code => 0x0448, lang => 'LANG_ORIYA', sublang => 'SUBLANG_ORIYA_INDIA', afx => 'AFX_TARG_ORI'},  # <ORI> <Oriya> <Oriya>
  'pl'      => {code => 0x0415, lang => 'LANG_POLISH', sublang => 'SUBLANG_POLISH_POLAND', afx => 'AFX_TARG_PLK'},  # <PLK> <Polish> <Polish>
  'pt-br'   => {code => 0x0416, lang => 'LANG_PORTUGUESE', sublang => 'SUBLANG_PORTUGUESE_BRAZILIAN', afx => 'AFX_TARG_PTB'},  # <PTB> <Portuguese> <Portuguese (Brazil)>
  'pt-pt'   => {code => 0x0816, lang => 'LANG_PORTUGUESE', sublang => 'SUBLANG_PORTUGUESE', afx => 'AFX_TARG_PTG'},  # <PTG> <Portuguese> <Portuguese (Portugal)>
  'pa'      => {code => 0x0446, lang => 'LANG_PUNJABI', sublang => 'SUBLANG_PUNJABI_INDIA', afx => 'AFX_TARG_PAN'},  # <PAN> <Punjabi> <Punjabi>
  'rm'      => {code => 0x0417, lang => 'LANG_ROMANSH', sublang => 'SUBLANG_ROMANSH_SWITZERLAND', afx => 'AFX_TARG_RMS'},  # <RMS> <Rhaeto-Romanic> <Rhaeto-Romanic>
  'ro'      => {code => 0x0418, lang => 'LANG_ROMANIAN', sublang => 'SUBLANG_ROMANIAN_ROMANIA', afx => 'AFX_TARG_ROM'},  # <ROM> <Romanian> <Romanian>
  'ro-md'   => {code => 0x0818, lang => '', sublang => '', afx => 'AFX_TARG_ROV'},  # <ROV> <Romanian> <Romanian (Moldova)>
  'ru'      => {code => 0x0419, lang => 'LANG_RUSSIAN', sublang=> 'SUBLANG_RUSSIAN_RUSSIA', afx => 'AFX_TARG_RUS', cp => 1251},  # <RUS> <Russian> <Russian>
  'ru-md'   => {code => 0x0819, lang => '', sublang => '', afx => 'AFX_TARG_RUM'},  # <RUM> <Russian> <Russian (Moldova)>
  'se'      => {code => 0x043b, lang => 'LANG_SAMI', sublang => 'SUBLANG_SAMI_NORTHERN_NORWAY', afx => 'AFX_TARG_SZI'},  # <SZI> <Sami> <Sami (Lappish)>  assuming == "Northern Sami"
  'sa'      => {code => 0x044f, lang => 'LANG_SANSKRIT', sublang => 'SUBLANG_SANSKRIT_INDIA', afx => 'AFX_TARG_SAN'},  # <SAN> <Sanskrit> <Sanskrit>
  'sr-cyrl' => {code => 0x0c1a, lang => 'LANG_SERBIAN', sublang => 'SUBLANG_SERBIAN_CYRILLIC', afx => 'AFX_TARG_SRB'},  # <SRB> <Serbian> <Serbian (Cyrillic)>
  'sr-latn' => {code => 0x081a, lang => 'LANG_SERBIAN', sublang => 'SUBLANG_SERBIAN_LATIN', afx => 'AFX_TARG_SRL'}, # <SRL> <Serbian> <Serbian (Latin)>
  'sd'      => {code => 0x0459, lang => '', sublang => '', afx => 'AFX_TARG_SND'},  # <SND> <Sindhi> <Sindhi>
  'sk'      => {code => 0x041b, lang => 'LANG_SLOVAK', sublang => 'SUBLANG_SLOVAK_SLOVAKIA', afx => 'AFX_TARG_SKY'},  # <SKY> <Slovak> <Slovak>
  'sl'      => {code => 0x0424, lang => 'LANG_SLOVENIAN', sublang => 'SUBLANG_SLOVENIAN_SLOVENIA', afx => 'AFX_TARG_SLV'},  # <SLV> <Slovenian> <Slovenian>
  'wen'     => {code => 0x042e, lang => 'LANG_UPPER_SORBIAN', sublang => 'SUBLANG_UPPER_SORBIAN_GERMANY'},  # language code is different (hsb)!!! <SBN> <Sorbian> <Sorbian>  # !!! 3 letters

  'es-es'   => {code => 0x040a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH', afx => 'AFX_TARG_ESP'},  # <ESP> <Spanish> <Spanish (Spain - Traditional Sort)>
  'es-mx'   => {code => 0x080a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_MEXICAN', afx => 'AFX_TARG_ESM'},  # <ESM> <Spanish> <Spanish (Mexico)>
  'es-es'   => {code => 0x0c0a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_MODERN', afx => 'AFX_TARG_ESN'},  # <ESN> <Spanish> <Spanish (Spain - Modern Sort)>
  'es-gt'   => {code => 0x100a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_GUATEMALA', afx => 'AFX_TARG_ESG'},  # <ESG> <Spanish> <Spanish (Guatemala)>
  'es-cr'   => {code => 0x140a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_COSTA_RICA', afx => 'AFX_TARG_ESC'},  # <ESC> <Spanish> <Spanish (Costa Rica)>
  'es-pa'   => {code => 0x180a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_PANAMA', afx => 'AFX_TARG_ESA'},  # <ESA> <Spanish> <Spanish (Panama)>
  'es-do'   => {code => 0x1c0a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_DOMINICAN_REPUBLIC', afx => 'AFX_TARG_ESD'},  # <ESD> <Spanish> <Spanish (Dominican Republic)>
  'es-ve'   => {code => 0x200a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_VENEZUELA', afx => 'AFX_TARG_ESV'},  # <ESV> <Spanish> <Spanish (Venezuela)>
  'es-co'   => {code => 0x240a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_COSTA_RICA', afx => 'AFX_TARG_ESO'},  # <ESO> <Spanish> <Spanish (Colombia)>
  'es-pe'   => {code => 0x280a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_PERU', afx => 'AFX_TARG_ESR'},  # <ESR> <Spanish> <Spanish (Peru)>
  'es-ar'   => {code => 0x2c0a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_ARGENTINA', afx => 'AFX_TARG_ESS'},  # <ESS> <Spanish> <Spanish (Argentina)>
  'es-ec'   => {code => 0x300a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_ECUADOR', afx => 'AFX_TARG_ESF'},  # <ESF> <Spanish> <Spanish (Ecuador)>
  'es-cl'   => {code => 0x340a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_CHILE', afx => 'AFX_TARG_ESL'},  # <ESL> <Spanish> <Spanish (Chile)>
  'es-uy'   => {code => 0x380a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_URUGUAY', afx => 'AFX_TARG_ESY'},  # <ESY> <Spanish> <Spanish (Uruguay)>
  'es-py'   => {code => 0x3c0a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_PARAGUAY', afx => 'AFX_TARG_ESZ'},  # <ESZ> <Spanish> <Spanish (Paraguay)>
  'es-bo'   => {code => 0x400a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_BOLIVIA', afx => 'AFX_TARG_ESB'},  # <ESB> <Spanish> <Spanish (Bolivia)>
  'es-sv'   => {code => 0x440a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_EL_SALVADOR', afx => 'AFX_TARG_ESE'},  # <ESE> <Spanish> <Spanish (El Salvador)>
  'es-hn'   => {code => 0x480a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_HONDURAS', afx => 'AFX_TARG_ESH'},  # <ESH> <Spanish> <Spanish (Honduras)>
  'es-ni'   => {code => 0x4c0a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_NICARAGUA', afx => 'AFX_TARG_ESI'},  # <ESI> <Spanish> <Spanish (Nicaragua)>
  'es-pr'   => {code => 0x500a, lang => 'LANG_SPANISH', sublang => 'SUBLANG_SPANISH_PUERTO_RICO', afx => 'AFX_TARG_ESU'},  # <ESU> <Spanish> <Spanish (Puerto Rico)>

  'gl'      => {code => 0x0456, lang => 'LANG_GALICIAN', sublang => 'SUBLANG_GALICIAN_GALICIAN', afx => 'AFX_TARG_ESP'},  # <ESP> <Galician> <Galician> !!! used AFX_TARG_ESP as I couldn't find any constant for Galician

  'st'      => {code => 0x0430, lang => '', sublang => '', afx => 'AFX_TARG_SXT'},  # <SXT> <Sutu> <Sutu>  == soto, sesotho
  'sw-ke'   => {code => 0x0441, lang => 'LANG_SWAHILI', sublang => 'SUBLANG_SWAHILI', afx => 'AFX_TARG_SWK'},  # <SWK> <Swahili> <Swahili (Kenya)>
  'sv'      => {code => 0x041D, lang => 'LANG_SWEDISH', sublang => 'SUBLANG_SWEDISH', afx => 'AFX_TARG_SVE'},  # <SVE> <Swedish> <Swedish>
  'sv-fi'   => {code => 0x081d, lang => 'LANG_SWEDISH', sublang => 'SUBLANG_SWEDISH_FINLAND', afx => 'AFX_TARG_SVF'},  # <SVF> <Swedish> <Swedish (Finland)>
  'ta'      => {code => 0x0449, lang => 'LANG_TAMIL', sublang => 'SUBLANG_TAMIL_INDIA', afx => 'AFX_TARG_TAM'},  # <TAM> <Tamil> <Tamil>
  'tt'      => {code => 0x0444, lang => 'LANG_TATAR', sublang => 'SUBLANG_TATAR_RUSSIA', afx => 'AFX_TARG_TAT'},  # <TAT> <Tatar> <Tatar (Tatarstan)>
  'te'      => {code => 0x044a, lang => 'LANG_TELUGU', sublang => 'SUBLANG_TELUGU_INDIA', afx => 'AFX_TARG_TEL'},  # <TEL> <Telugu> <Telugu>
  'th'      => {code => 0x041E, lang => 'LANG_THAI', sublang => 'SUBLANG_THAI_THAILAND', afx => 'AFX_TARG_THA'},  # <THA> <Thai> <Thai>
  'ts'      => {code => 0x0431, lang => '', sublang => '', afx => 'AFX_TARG_TSG'},  # <TSG> <Tsonga> <Tsonga>    (not Tonga!)
  'tn'      => {code => 0x0432, lang => 'LANG_TSWANA', sublang => 'SUBLANG_TSWANA_SOUTH_AFRICA', afx => 'AFX_TARG_TNA'},  # <TNA> <Tswana> <Tswana>    == Setswana
  'tr'      => {code => 0x041f, lang => 'LANG_TURKISH', sublang => 'SUBLANG_TURKISH_TURKEY', afx => 'AFX_TARG_TRK', cp => 1254},  # <TRK> <Turkish> <Turkish>
  'uk'      => {code => 0x0422, lang => 'LANG_UKRAINIAN', sublang => 'SUBLANG_UKRAINIAN_UKRAINE', afx => 'AFX_TARG_UKR'},  # <UKR> <Ukrainian> <Ukrainian>
  'ur-pk'   => {code => 0x0420, lang => 'LANG_URDU', sublang => 'SUBLANG_URDU_PAKISTAN', afx => 'AFX_TARG_URD'},  # <URD> <Urdu> <Urdu (Pakistan)>
  'ur-in'   => {code => 0x0820, lang => 'LANG_URDU', sublang => 'SUBLANG_URDU_INDIA', afx => 'AFX_TARG_URI'},  # <URI> <Urdu> <Urdu (India)>
  'uz-latn' => {code => 0x0443, lang => 'LANG_UZBEK', sublang => 'SUBLANG_UZBEK_LATIN', afx => 'AFX_TARG_UZB'},  # <UZB> <Uzbek> <Uzbek (Latin)>
  'uz-cyrl' => {code => 0x0843, lang => 'LANG_UZBEK', sublang => 'SUBLANG_UZBEK_CYRILLIC', afx => 'AFX_TARG_UZC'},  # <UZC> <Uzbek> <Uzbek (Cyrillic)>
  'ven'     => {code => 0x0433, lang => '', sublang => '', afx => 'AFX_TARG_VEN'},  # <VEN> <Venda> <Venda>
  'vi'      => {code => 0x042a, lang => 'LANG_VIETNAMESE', sublang => 'SUBLANG_VIETNAMESE_VIETNAM', afx => 'AFX_TARG_VIT', cp => 1258},  # <VIT> <Vietnamese> <Vietnamese>
  'xh'      => {code => 0x0434, lang => 'LANG_XHOSA', sublang => 'SUBLANG_XHOSA_SOUTH_AFRICA', afx => 'AFX_TARG_XHS'},  # <XHS> <Xhosa> <Xhosa>
  'yi'      => {code => 0x043d, lang => '', sublang => '', afx => 'AFX_TARG_JII'},  # <JII> <Yiddish> <Yiddish>  # formetly ji
  'zu'      => {code => 0x0435, lang => 'LANG_ZULU', sublang => 'SUBLANG_ZULU_SOUTH_AFRICA', afx => 'AFX_TARG_ZUL'},  # <ZUL> <Zulu> <Zulu>
);

1;