fx_version 'cerulean'
game 'gta5'
name 'Prospecting System'
author 'glitchdetector & tj_antisocial_rider'
description 'A modern and flexible prospecting resource for QBCore with dynamic target generation in multiple areas.'
version '1.1.0'

shared_scripts {
    'config.lua' -- Configuration file, shared between client and server
}

server_scripts {
    'server/interface.lua',        -- Interface for other resources to interact with prospecting
    'server/sv_*.lua'       -- Includes sv_locations.lua and sv_prospecting.lua
}

client_scripts 'client/cl_*.lua' -- Includes cl_prospect.lua and cl_prospecting.lua

file 'stream/gen_w_am_metaldetector.ytyp' -- YTYP file for the metal detector model

server_exports {
    'AddProspectingTarget',  -- x, y, z, data (data should now include item, valuable, and difficulty)
    'AddProspectingTargets', -- list (list of tables, each with x, y, z, and data)
    'StartProspecting',      -- player
    'StopProspecting',       -- player
    'IsProspecting',         -- player
    'SetDifficulty',         -- modifier (resource-specific difficulty for scanner)
}