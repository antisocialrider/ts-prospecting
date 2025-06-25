fx_version 'cerulean'
game 'gta5'
name 'Prospecting System'
author 'glitchdetector & tj_antisocial_rider'
description 'A modern and flexible prospecting resource for FiveM with dynamic target generation in multiple areas.'
version '1.1.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    'server/interface.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

data_file 'DLC_ITYP_REQUEST' 'stream/prop_metaldetector.ytyp'

server_exports {
    'AddProspectingTarget',
    'AddProspectingTargets',
    'StartProspecting',
    'StopProspecting',
    'IsProspecting',
    'SetDifficulty',
}