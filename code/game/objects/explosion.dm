//TODO: Flash range does nothing currently
//We used to use linear regression to approximate the answer, but Mloc realized this was actually faster.
//And lo and behold, it is, and it's more accurate to boot.
proc/explosion(turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, flash_range, flame_range = 2, adminlog = 1, z_transfer = UP|DOWN, shaped)
	var/multi_z_scalar = 0.35
	src = null	//so we don't abort once src is deleted
	spawn(0)
		var/start = world.timeofday
		epicenter = get_turf(epicenter)
		if(!epicenter) return
		explosion_in_progress = 1
//		var/loopbreak = 0
//		while(explosion_in_progress)
//			if(loopbreak > 10)
//				loopbreak = 0
//			loopbreak++
//			sleep(2)

		// Handles recursive propagation of explosions.
		if(z_transfer)
			var/adj_dev   = max(0, (multi_z_scalar * devastation_range) - (shaped ? 2 : 0) )
			var/adj_heavy = max(0, (multi_z_scalar * heavy_impact_range) - (shaped ? 2 : 0) )
			var/adj_light = max(0, (multi_z_scalar * light_impact_range) - (shaped ? 2 : 0) )
			var/adj_flash = max(0, (multi_z_scalar * flash_range) - (shaped ? 2 : 0) )
			var/adj_flame = max(0, (multi_z_scalar * flame_range) - (shaped ? 2 : 0) )

			if(adj_dev > 0 || adj_heavy > 0)
				if(HasAbove(epicenter.z) && z_transfer & UP)
					explosion(GetAbove(epicenter), round(adj_dev), round(adj_heavy), round(adj_light), round(adj_flash), round(adj_flame), 0, UP, shaped)
				if(HasBelow(epicenter.z) && z_transfer & DOWN)
					explosion(GetBelow(epicenter), round(adj_dev), round(adj_heavy), round(adj_light), round(adj_flash), round(adj_flame), 0, DOWN, shaped)

		var/max_range = max(devastation_range, heavy_impact_range, light_impact_range, flash_range, flame_range)

		sleep(-1)

		// Play sounds; we want sounds to be different depending on distance so we will manually do it ourselves.
		// Stereo users will also hear the direction of the explosion!
		// Calculate far explosion sound range. Only allow the sound effect for heavy/devastating explosions.
		// 3/7/14 will calculate to 80 + 35
		var/far_dist = 0
		far_dist += heavy_impact_range * 5
		far_dist += devastation_range * 20
		var/frequency = get_rand_frequency()
		for(var/mob/M in GLOB.player_list)
			if(M.z == epicenter.z)
				var/turf/M_turf = get_turf(M)
				var/dist = get_dist(M_turf, epicenter)
				// If inside the blast radius + world.view - 2
				if(dist <= round(max_range + world.view - 2, 1))
					M.playsound_local(epicenter, get_sfx("explosion"), 100, 1, frequency, falloff = 5) // get_sfx() is so that everyone gets the same sound
				else if(dist <= far_dist)
					var/far_volume = Clamp(far_dist, 30, 50) // Volume is based on explosion size and dist
					far_volume += (dist <= far_dist * 0.5 ? 50 : 0) // add 50 volume if the mob is pretty close to the explosion
					M.playsound_local(epicenter, 'sound/effects/explosionfar.ogg', far_volume, 1, frequency, falloff = 5)

//		var/postponeCycles = max(round(max_range/2),8)
//		lightingProcess.postpone(postponeCycles)
//		machineryProcess.postpone(postponeCycles)

		if(adminlog)
			message_admins("Explosion with size ([devastation_range], [heavy_impact_range], [light_impact_range]) in area [epicenter.loc.name] ([epicenter.x],[epicenter.y],[epicenter.z]) (<A HREF='?_src_=holder;adminplayerobservecoodjump=1;X=[epicenter.x];Y=[epicenter.y];Z=[epicenter.z]'>JMP</a>)")
			log_game("Explosion with size ([devastation_range], [heavy_impact_range], [light_impact_range]) in area [epicenter.loc.name] ")

		var/approximate_intensity = (devastation_range * 3) + (heavy_impact_range * 2) + light_impact_range
		// Large enough explosion. For performance reasons, powernets will be rebuilt manually
		if(!defer_powernet_rebuild && (approximate_intensity > 25))
			defer_powernet_rebuild = 1

		if(heavy_impact_range > 1)
			var/datum/effect/system/explosion/E = new/datum/effect/system/explosion()
			E.set_up(epicenter)
			E.start()

		var/x0 = epicenter.x
		var/y0 = epicenter.y
		var/z0 = epicenter.z
		if(config.use_recursive_explosions)
			var/power = devastation_range * 2 + heavy_impact_range + light_impact_range //The ranges add up, ie light 14 includes both heavy 7 and devestation 3. So this calculation means devestation counts for 4, heavy for 2 and light for 1 power, giving us a cap of 27 power.
			explosion_rec(epicenter, power, shaped)
		else
			. = list()
			//flash mobs
			if(flash_range)
				for(var/mob/living/L in viewers(flash_range, epicenter))
					L.flash_eyes()
			. = trange(max_range, epicenter)
			for(var/TU in .)
				var/turf/T = TU
				if (!T)
					continue

				var/dist = sqrt((T.x - x0)**2 + (T.y - y0)**2)

				if(dist < devastation_range)		dist = 1
				else if(dist < heavy_impact_range)	dist = 2
				else if(dist < light_impact_range)	dist = 3
				else								continue
				fireyexplosion(flame_range, T)
				for(var/atom/movable/AM in T.contents)	//bypass type checking since only atom/movable can be contained by turfs anyway
					if(AM && AM.simulated)	AM.ex_act(dist)

				T.ex_act(dist)
				CHECK_TICK2(90)


		var/took = (world.timeofday-start)/10
		//You need to press the DebugGame verb to see these now....they were getting annoying and we've collected a fair bit of data. Just -test- changes  to explosion code using this please so we can compare
		if(Debug2) world.log << "## DEBUG: Explosion([x0],[y0],[z0])(d[devastation_range],h[heavy_impact_range],l[light_impact_range]): Took [took] seconds."
		explosion_in_progress = 0

		sleep(8)
	return 1


/proc/fireyexplosion(var/flame_range, var/turf/T)
	set waitfor = 0
	if(flame_range && prob(40) && !isspace(T) && !T.density)
		var/obj/fire/F = new(T)
		sleep(rand(5, 10))
		qdel(F)

proc/secondaryexplosion(turf/epicenter, range)
	for(var/turf/tile in trange(range, epicenter))
		tile.ex_act(2)
		sleep(2)
/*
/proc/GatherSpiralTurfs(range, turf/epicenter)
	. = spiral_range_turfs(range, epicenter, tick_checked = TRUE)
*/