#!/usr/bin/env -S nu --no-config-file --stdin

# Download SVG and export icon in all formats.
def main [] {
    const data = path self | path dirname --num-levels 2 | path join "data"
    mkdir $"($data)/image" $"($data)/public"

    http get "https://raw.githubusercontent.com/phosphor-icons/core/refs/heads/main/assets/bold/faders-bold.svg"
    | str replace "currentColor" "#c084fc" | save --force $"($data)/public/favicon.svg"
    magick -background none $"($data)/public/favicon.svg" -background none -resize 192x192 $"($data)/public/favicon.ico"
    
    let background = '<rect fill="#fff6ea" height="100%" rx="30" ry="30" width="100%" />'
    open $"($data)/public/favicon.svg" | str replace "<path" $"($background)<path"
    | save --force $"($data)/image/icon.svg"
    magick $"($data)/image/icon.svg" -background none -resize 192x192 $"($data)/image/icon.ico"
    magick $"($data)/image/icon.svg" -background none -resize 192x192 $"($data)/image/icon.png"

    if $nu.os-info.name == "macos" {
        # Sips icns file generation only works for specific resolutions.
        let temp = mktemp --tmpdir --suffix ".png"
        magick $"($data)/image/icon.svg" -background none -resize 256x256 $temp
        sips -s format icns $temp --out $"($data)/image/icon.icns"
    }
}
