fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'XS-Trucking'
author 'XyraL'
description 'Trucking job for Qbox and QBCore: trucking spots and routes built in game, skills, certificates, co-op, businesses and illegal runs.'
version '3.0.0'

dependencies {
    'ox_lib',
    'oxmysql',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    'bridge/framework.lua',
    'bridge/target.lua',
    'bridge/keys.lua',
    'bridge/fuel.lua',
    'bridge/dispatch.lua',
    'client/ui.lua',
    'client/paths.lua',
    'client/main.lua',
    'client/placement.lua',
    'client/job.lua',
    'client/builder.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/framework.lua',
    'bridge/keys.lua',
    'bridge/dispatch.lua',
    'bridge/inventory.lua',
    'server/db.lua',
    'server/settings.lua',
    'server/spots.lua',
    'server/progress.lua',
    'server/business.lua',
    'server/garage.lua',
    'server/jobs.lua',
    'server/coop.lua',
    'server/callbacks.lua',
    'server/admin.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/vendor/leaflet/leaflet.js',
    'html/vendor/leaflet/leaflet.css',
    'html/vendor/leaflet/images/*.png',
    'html/assets/maps/tiles/*.webp',
}
