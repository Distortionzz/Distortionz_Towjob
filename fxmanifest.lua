fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Distortionz'
description 'Distortionz Tow Job - Premium tow operator job with dispatch calls, flatbed handout, and yard-delivery payout.'
version '1.2.3'
repository 'https://github.com/Distortionzz/Distortionz_Towjob'

ui_page 'html/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua',
    'version_check.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sounds/*.ogg',
    'html/sounds/*.mp3',
    'html/sounds/*.wav'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target'
}
