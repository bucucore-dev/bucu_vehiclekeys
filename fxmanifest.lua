fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'bucu_vehiclekeys'
description 'BUCU Core Vehicle Key Security, Remote Lock/Unlock & Anti-Theft Lockpick'
author 'BUCU Framework Team'
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js'
}

shared_scripts {
    '@bucu_shared/shared/constants.lua',
    '@bucu_shared/shared/config.lua',
    'config.lua',
    'locales/en.lua',
    'locales/id.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/bridge.lua'
}

dependencies {
    'bucu_shared',
    'bucu_core',
    'bucu_inventory'
}

client_exports {
    'GiveKey',
    'HasKey',
    'RemoveKey'
}

server_exports {
    'GiveKey',
    'HasKey',
    'RemoveKey'
}

