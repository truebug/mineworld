## CN-first locale helper. Web reads localStorage.mw_lang (default zh).
extends Node

const LANG_KEY := "mw_lang"


func lang() -> String:
	"""Return zh|en; default Chinese."""
	if OS.has_feature("web"):
		var raw := str(JavaScriptBridge.eval(
			"(function(){try{var v=localStorage.getItem('mw_lang');"
			+ "return (v==='en'||v==='zh')?v:'zh';}catch(e){return 'zh';}})()",
			true
		)).strip_edges()
		if raw == "en" or raw == "zh":
			return raw
	return "zh"


func is_zh() -> bool:
	"""True when Chinese (default)."""
	return lang() != "en"


func t(zh: String, en: String) -> String:
	"""Pick Chinese or English string (no bilingual mash when zh)."""
	return zh if is_zh() else en
