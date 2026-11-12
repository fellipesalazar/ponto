#!/bin/bash
# Compila o Ponto e gera os arquivos de uma versão:
#   dist/Ponto.pkg  instalador
#   dist/Ponto.zip  o app, usado pela atualização automática
# Uso: bash tools/build.sh   (precisa de um Mac com as ferramentas da Apple)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
APP="build/Ponto.app"
echo "Ponto $VERSION, macOS $(sw_vers -productVersion), kit $(xcrun --show-sdk-version)"
xcrun swiftc --version

rm -rf build dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

# Um binário pra cada tipo de Mac, depois junta os dois.
for ARCH in arm64 x86_64; do
    echo "Compilando ($ARCH)..."
    xcrun swiftc -O -swift-version 5 \
        -target "${ARCH}-apple-macos13.0" \
        -o "build/Ponto-$ARCH" \
        Sources/Ponto/*.swift
done
lipo -create build/Ponto-arm64 build/Ponto-x86_64 -output "$APP/Contents/MacOS/Ponto"

echo "Desenhando o ícone..."
python3 -m venv build/venv
build/venv/bin/pip install --quiet pillow
build/venv/bin/python tools/make_icon.py "$APP/Contents/Resources/AppIcon.icns"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Empacotando..."
ditto -c -k --keepParent "$APP" dist/Ponto.zip

mkdir -p build/root/Applications
cp -R "$APP" build/root/Applications/
pkgbuild --analyze --root build/root build/component.plist
# Sem isso o instalador pode colocar o app em outra pasta onde já exista um Ponto.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" build/component.plist
pkgbuild --root build/root \
    --component-plist build/component.plist \
    --identifier br.com.ponto.lembrete.instalador \
    --version "$VERSION" \
    --install-location / \
    --scripts tools/pkg-scripts \
    dist/Ponto.pkg

ls -lh dist
echo "Pronto: Ponto $VERSION"
