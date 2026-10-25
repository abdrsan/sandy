# Подключается из bundle.sh и test.sh: `source "$ROOT/Scripts/sdk.sh"`.
#
# Зачем. В SDK macOS 27 SwiftUI объявляет `@State` не только обёрткой, но и
# макросом — `#externalMacro(module: "SwiftUIMacros", ...)`, и компилятор
# выбирает макрос. Плагин `libSwiftUIMacros.dylib` ставится только с Xcode,
# в Command Line Tools его нет, и сборка падает на каждом `@State`:
# `plugin for module 'SwiftUIMacros' not found`. Код тут ни при чём.
#
# Что делает. Если плагина в тулчейне нет, а в SDK по умолчанию `@State` уже
# макрос, — выставляет SDKROOT на самый свежий SDK рядом, где `@State` ещё
# обёртка: CLT 27 кладёт рядом и 26.x. Свой SDKROOT не трогает.
#
# Xcode сюда не попадает: плагины у него лежат в Toolchains, а не в самом
# каталоге разработчика, и папки, которую проверяет первое условие, у него
# просто нет — значит и подстановки не будет.
#
# Пути берутся из `xcode-select -p`, а он слушает DEVELOPER_DIR. Поэтому обе
# ветки проверяются на поддельном каталоге, без macOS 27 под рукой:
#   DEVELOPER_DIR=/tmp/clt-27 ./Scripts/bundle.sh release

sandy_sdk_has_state_macro() {
    grep -qs 'type: "StateMacro"' \
        "$1"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*.swiftinterface
}

if [ -z "${SDKROOT:-}" ]; then
    _DEVELOPER="$(xcode-select -p 2>/dev/null)"
    _DEVELOPER="${_DEVELOPER%/}"
    _PLUGINS="$_DEVELOPER/usr/lib/swift/host/plugins"
    if [ -d "$_PLUGINS" ] && [ ! -e "$_PLUGINS/libSwiftUIMacros.dylib" ] \
        && sandy_sdk_has_state_macro "$_DEVELOPER/SDKs/MacOSX.sdk"; then
        _FALLBACK=""
        # Версии по убыванию; симлинки вида MacOSX.sdk и MacOSX26.sdk
        # отсекает шаблон с точкой.
        for _SDK in $(ls -d "$_DEVELOPER"/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -V -r); do
            if ! sandy_sdk_has_state_macro "$_SDK"; then
                _FALLBACK="$_SDK"
                break
            fi
        done
        if [ -n "$_FALLBACK" ]; then
            echo "==> Command Line Tools без плагина SwiftUIMacros: собираю с $(basename "$_FALLBACK")"
            export SDKROOT="$_FALLBACK"
        else
            # Одинарные кавычки: в двойных обратные кавычки вокруг @State
            # прочитались бы как подстановка команды, и имя пропало бы из
            # сообщения (#124).
            echo '!!! `@State` в SDK — макрос из SwiftUIMacros, а плагина в тулчейне нет,' >&2
            echo '    и более старого SDK рядом тоже нет. Поставьте Xcode' >&2
            echo '    или задайте SDKROOT вручную.' >&2
            exit 1
        fi
        unset _SDK _FALLBACK
    fi
    unset _DEVELOPER _PLUGINS
fi

# Some CLT upgrades leave older private PackageDescription interfaces beside
# current public ones. Swift prefers the private interface, then cannot find
# Swift 6 APIs or link the manifest. Use a local copy with public interfaces;
# never change the installed toolchain or an explicitly configured override.
if [ -z "${SWIFTPM_CUSTOM_LIBS_DIR:-}" ]; then
    _SANDY_DEVELOPER="$(xcode-select -p 2>/dev/null)"
    _SANDY_MANIFEST="${_SANDY_DEVELOPER%/}/usr/lib/swift/pm/ManifestAPI"
    for _SANDY_PRIVATE in "$_SANDY_MANIFEST"/PackageDescription.swiftmodule/*.private.swiftinterface; do
        [ -f "$_SANDY_PRIVATE" ] || continue
        _SANDY_PUBLIC="${_SANDY_PRIVATE%.private.swiftinterface}.swiftinterface"
        if grep -q 'func swiftLanguageMode(' "$_SANDY_PUBLIC" \
            && ! grep -q 'func swiftLanguageMode(' "$_SANDY_PRIVATE"; then
            _SANDY_LIBS="$ROOT/.build/swiftpm-libs"
            mkdir -p "$_SANDY_LIBS" || exit 1
            cp -R "$_SANDY_MANIFEST" "$_SANDY_LIBS/" || exit 1
            find "$_SANDY_LIBS/ManifestAPI" -name '*.private.swiftinterface' -delete || exit 1
            export SWIFTPM_CUSTOM_LIBS_DIR="$_SANDY_LIBS"
            echo "==> Command Line Tools: using current SwiftPM interfaces from .build/swiftpm-libs"
            break
        fi
    done
    unset _SANDY_DEVELOPER _SANDY_MANIFEST _SANDY_PRIVATE _SANDY_PUBLIC _SANDY_LIBS
fi
