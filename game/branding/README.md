# Rally Fans Map

Канонический векторный логотип хранится в `rfm-icon.svg`; сайт бренда — https://rallyfansmap.ru/.
Web-сборка копирует этот SVG в `dist/favicon.svg` и использует его как favicon
и логотип на собственном чёрном экране загрузки. Текст — **Rally Fans Map**,
цвет полосы прогресса — **#ff3b0a**. Полоса обновляется по событиям загрузчика Godot;
при неизвестном размере загрузки показывается движущийся индикатор.

`rfm-splash.png` — растровый экран с тем же логотипом и надписью для внутреннего
boot splash Godot. PNG нужен движку для splash; SVG остаётся источником favicon.
Apple touch icon экспортируется Godot из канонического SVG.

`rfm-icon-server.svg` — тот же логотип с обратными цветами (оранжевый на
белом) для серверной сборки «SERVER Rally Fans Simulator» (docs/DEDICATED_SERVER.md).
