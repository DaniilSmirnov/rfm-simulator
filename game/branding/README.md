# Rally Fans Map

Канонический векторный логотип хранится в `rfm-icon.svg`; сайт бренда — https://rallyfansmap.ru/.
Web-сборка копирует этот SVG в `dist/favicon.svg` и использует его как favicon
и логотип на собственном чёрном экране загрузки. Текст — **Rally Fans Map**,
цвет полосы прогресса — **#ff3b0a**. Полоса обновляется по событиям загрузчика Godot;
при неизвестном размере загрузки показывается движущийся индикатор.

`rfm-splash.png` — растровый экран с тем же логотипом и надписью для внутреннего
boot splash Godot. PNG нужен движку для splash; SVG остаётся источником favicon.
Apple touch icon экспортируется Godot из канонического SVG.

`rfm-icon-macos.icns` — иконка macOS-сборок (presets «macOS» и «macOS Demo»): тот же логотип
на сетке Apple (squircle 824 на холсте 1024, прозрачные поля и тень), чтобы в Dock она была
одного размера с другими приложениями. Пересобрать: `python3 scripts/make-macos-icon.py` (нужен Pillow).

`rfm-icon-server-macos.icns` — то же, но с поменянными цветами (оранжевый логотип на белом):
иконка серверного приложения «SERVER Rally Fans Simulator» (preset «macOS Server»,
[DEDICATED_SERVER.md](../../docs/DEDICATED_SERVER.md)). Её пишет тот же скрипт.
