fx_version 'cerulean'
game 'gta5'

author 'TwoPoint Development'
description 'Standalone Tow Duty, Queue & Company Rotation System'
version '1.8.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}


ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'phone/index.html',
    'phone/style.css',
    'phone/app.js',
    'phone/icon.svg',
    'phone/icon.png',
    'phone/icon_128.png'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}
