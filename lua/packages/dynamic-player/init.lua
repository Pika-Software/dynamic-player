import( gpm.PackageExists( "packages/player-extensions" ) and "packages/player-extensions" or "https://github.com/Pika-Software/player-extensions" )
if not SERVER then return end
include( "server.lua" )