#<< genres/*

class app.App
	constructor:->
		console.log "App created!"
		new genres.Progressive
		new genres.TripHop

new app.App