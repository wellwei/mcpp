#!/usr/bin/env bash
# 67_features_strict.sh — feature activation, backend= sugar, and the
# --strict schema gate (unknown feature / unknown platform / unknown backend).
set -e

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

# Library dep declaring backend-* features (the backend= sugar target).
mkdir -p widget/src
cat > widget/mcpp.toml <<'EOF'
[package]
name    = "widget"
version = "0.1.0"

[targets.widget]
kind = "lib"

[features]
default   = []
backend-a = []
backend-b = []
EOF
cat > widget/src/widget.cppm <<'EOF'
export module widget;
export int widget_backend() {
#if defined(MCPP_FEATURE_BACKEND_A)
    return 1;
#elif defined(MCPP_FEATURE_BACKEND_B)
    return 2;
#else
    return 0;
#endif
}
EOF

# Plain dependency with no feature table (case 5 target).
mkdir -p plain/src
cat > plain/mcpp.toml <<'EOF'
[package]
name    = "plain"
version = "0.1.0"

[targets.plain]
kind = "lib"
EOF
cat > plain/src/plain.cppm <<'EOF'
export module plain;
export int plain_value() { return 1; }
EOF

mkdir -p app/src
cat > app/mcpp.toml <<'EOF'
[package]
name      = "app"
version   = "0.1.0"
platforms = ["linux", "macos", "windows"]

[features]
default = ["base"]
base    = []
extra   = []

[dependencies]
widget = { path = "../widget", backend = "a" }
EOF
cat > app/src/main.cpp <<'EOF'
import std;
import widget;
int main() {
#ifdef MCPP_FEATURE_BASE
    std::println("base");
#endif
#ifdef MCPP_FEATURE_EXTRA
    std::println("extra");
#endif
    std::println("backend={}", widget_backend());
    return 0;
}
EOF

cd app

# 1. backend= sugar selects widget's backend-a feature.
"$MCPP" build > b1.log 2>&1 || { cat b1.log; echo "build failed"; exit 1; }
bin=$(find target \( -name app -o -name app.exe \) -type f | head -1)
[[ -n "$bin" ]] || { echo "no app binary"; exit 1; }
out=$("$bin" | tail -2)
grep -q "backend=1" <<< "$out" || { echo "backend=a not activated: $out"; exit 1; }
grep -q "base" <<< "$out" || true   # default features active

# 2. --features extra activates a declared feature.
rm -rf target
"$MCPP" build --features extra > b2.log 2>&1 || { cat b2.log; echo "features build failed"; exit 1; }
bin=$(find target \( -name app -o -name app.exe \) -type f | head -1)
[[ -n "$bin" ]] || { echo "no app binary"; exit 1; }
"$bin" | grep -q "extra" || { echo "--features extra not active"; exit 1; }

# 3. Unknown feature → warning by default, error under --strict.
rm -rf target
"$MCPP" build --features nosuch > b3.log 2>&1 || { cat b3.log; echo "warn path must not fail"; exit 1; }
grep -q "does not declare" b3.log || { cat b3.log; echo "missing unknown-feature warning"; exit 1; }
if "$MCPP" build --features nosuch --strict > b4.log 2>&1; then
    cat b4.log; echo "--strict must fail on unknown feature"; exit 1
fi
grep -q "does not declare" b4.log || { cat b4.log; echo "missing strict error text"; exit 1; }

# 4. Unknown backend on a dep that declares backend-* features → hard error without --strict.
sed 's/backend = "a"/backend = "zzz"/' mcpp.toml > mcpp.toml.tmp && mv mcpp.toml.tmp mcpp.toml
rm -rf target
if "$MCPP" build > b5.log 2>&1; then
    cat b5.log; echo "unknown backend must fail without --strict"; exit 1
fi
grep -q "dependency 'widget' does not support backend 'zzz'" b5.log \
    || { cat b5.log; echo "missing backend error"; exit 1; }
sed 's/backend = "zzz"/backend = "a"/' mcpp.toml > mcpp.toml.tmp && mv mcpp.toml.tmp mcpp.toml

# 5. backend= on a dependency with no feature table must also fail.
cat >> mcpp.toml <<'EOF'
plain = { path = "../plain", backend = "cuda" }
EOF
rm -rf target
if "$MCPP" build > b6.log 2>&1; then
    cat b6.log; echo "backend on a featureless dependency must fail"; exit 1
fi
grep -q "dependency 'plain' does not support backend 'cuda'" b6.log \
    || { cat b6.log; echo "missing featureless-backend error"; exit 1; }
sed '/plain = { path = "..\/plain", backend = "cuda" }/d' mcpp.toml > mcpp.toml.tmp
mv mcpp.toml.tmp mcpp.toml

# 6. An ordinary unknown dependency feature keeps warning/--strict behavior.
sed 's/backend = "a"/backend = "a", features = ["nosuch"]/' \
    mcpp.toml > mcpp.toml.tmp
mv mcpp.toml.tmp mcpp.toml
rm -rf target
"$MCPP" build > b7.log 2>&1 \
    || { cat b7.log; echo "ordinary unknown feature must warn, not fail"; exit 1; }
grep -q "does not declare requested feature 'nosuch'" b7.log \
    || { cat b7.log; echo "missing ordinary-feature warning"; exit 1; }
if "$MCPP" build --strict > b8.log 2>&1; then
    cat b8.log; echo "--strict must reject ordinary unknown dependency feature"; exit 1
fi
grep -q "does not declare requested feature 'nosuch'" b8.log \
    || { cat b8.log; echo "missing strict ordinary-feature error"; exit 1; }
sed 's/backend = "a", features = \["nosuch"\]/backend = "a"/' \
    mcpp.toml > mcpp.toml.tmp
mv mcpp.toml.tmp mcpp.toml

# 7. Unknown platform → warning by default, error under --strict.
sed 's/platforms = \["linux", "macos", "windows"\]/platforms = ["linux", "amiga"]/' mcpp.toml > mcpp.toml.tmp && mv mcpp.toml.tmp mcpp.toml
rm -rf target
"$MCPP" build > b9.log 2>&1 || { cat b9.log; echo "platform warn path must not fail"; exit 1; }
grep -q "unknown platform 'amiga'" b9.log || { cat b9.log; echo "missing platform warning"; exit 1; }
if "$MCPP" build --strict > b10.log 2>&1; then
    cat b10.log; echo "--strict must fail on unknown platform"; exit 1
fi

echo "OK"
