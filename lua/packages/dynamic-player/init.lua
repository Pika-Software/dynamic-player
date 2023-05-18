import( gpm.PackageExists( "packages/player-extensions" ) and "packages/player-extensions" or "https://github.com/Pika-Software/player-extensions" )

if SERVER then
    include( "server.lua" )
end