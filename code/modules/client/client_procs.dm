#define UPLOAD_LIMIT			1000000	//Restricts client uploads to the server to 1MB
#define UPLOAD_LIMIT_ADMIN		10000000	//Restricts admin uploads to the server to 10MB

#define MIN_RECOMMENDED_CLIENT 1526
#define REQUIRED_CLIENT_MAJOR 513
#define REQUIRED_CLIENT_MINOR 1493

#define LIMITER_SIZE	5
#define CURRENT_SECOND	1
#define SECOND_COUNT	2
#define CURRENT_MINUTE	3
#define MINUTE_COUNT	4
#define ADMINSWARNED_AT	5
	/*
	When somebody clicks a link in game, this Topic is called first.
	It does the stuff in this proc and  then is redirected to the Topic() proc for the src=[0xWhatever]
	(if specified in the link). ie locate(hsrc).Topic()

	Such links can be spoofed.

	Because of this certain things MUST be considered whenever adding a Topic() for something:
		- Can it be fed harmful values which could cause runtimes?
		- Is the Topic call an admin-only thing?
		- If so, does it have checks to see if the person who called it (usr.client) is an admin?
		- Are the processes being called by Topic() particularly laggy?
		- If so, is there any protection against somebody spam-clicking a link?
	*/

/client/Topic(href, href_list, hsrc)
	if(!usr || usr != mob)	//stops us calling Topic for somebody else's client. Also helps prevent usr=null
		return

	//Asset cache
	var/asset_cache_job
	if(href_list["asset_cache_confirm_arrival"])
		asset_cache_job = asset_cache_confirm_arrival(href_list["asset_cache_confirm_arrival"])
		if (!asset_cache_job)
			return

	// Rate limiting
	var/mtl = CONFIG_GET(number/minute_topic_limit)
	if (!holder && mtl)
		var/minute = round(world.time, 600)
		if (!topiclimiter)
			topiclimiter = new(LIMITER_SIZE)
		if (minute != topiclimiter[CURRENT_MINUTE])
			topiclimiter[CURRENT_MINUTE] = minute
			topiclimiter[MINUTE_COUNT] = 0
		topiclimiter[MINUTE_COUNT] += 1
		if (topiclimiter[MINUTE_COUNT] > mtl)
			var/msg = "Your previous action was ignored because you've done too many in a minute."
			if (minute != topiclimiter[ADMINSWARNED_AT]) //only one admin message per-minute. (if they spam the admins can just boot/ban them)
				topiclimiter[ADMINSWARNED_AT] = minute
				msg += " Administrators have been informed."
				log_game("[key_name(src)] Has hit the per-minute topic limit of [mtl] topic calls in a given game minute")
				message_admins("[ADMIN_LOOKUPFLW(usr)] [ADMIN_KICK(usr)] Has hit the per-minute topic limit of [mtl] topic calls in a given game minute")
			to_chat(src, "<span class='danger'>[msg]</span>")
			return
	var/stl = CONFIG_GET(number/second_topic_limit)
	if (!holder && stl)
		var/second = round(world.time, 10)
		if (!topiclimiter)
			topiclimiter = new(LIMITER_SIZE)
		if (second != topiclimiter[CURRENT_SECOND])
			topiclimiter[CURRENT_SECOND] = second
			topiclimiter[SECOND_COUNT] = 0
		topiclimiter[SECOND_COUNT] += 1
		if (topiclimiter[SECOND_COUNT] > stl)
			to_chat(src, "<span class='danger'>Your previous action was ignored because you've done too many in a second</span>")
			return
	//Logs all hrefs, except chat pings
	if(!(href_list["_src_"] == "chat" && href_list["proc"] == "ping" && LAZYLEN(href_list) == 2))
		log_href("[src] (usr:[usr]\[[COORD(usr)]\]) : [hsrc ? "[hsrc] " : ""][href]")
	//byond bug ID:2256651
	if (asset_cache_job && (asset_cache_job in completed_asset_jobs))
		to_chat(src, "<span class='danger'>An error has been detected in how your client is receiving resources. Attempting to correct.... (If you keep seeing these messages you might want to close byond and reconnect)</span>")
		src << browse("...", "window=asset_cache_browser")
		return
	if (href_list["asset_cache_preload_data"])
		asset_cache_preload_data(href_list["asset_cache_preload_data"])
		return


	//Admin PM
	if(href_list["priv_msg"])
		private_message(href_list["priv_msg"], null)
		return


	switch(href_list["_src_"])
		if("holder")
			hsrc = holder
		if("usr")
			hsrc = mob
		if("prefs")
			if(inprefs)
				return
			inprefs = TRUE
			. = prefs.process_link(usr, href_list)
			inprefs = FALSE
			return
		if("vars")
			return view_var_Topic(href, href_list, hsrc)
		if("chat")
			return chatOutput.Topic(href, href_list)
		if("vote")
			return SSvote.Topic(href, href_list)
		if("codex")
			return SScodex.Topic(href, href_list)

	switch(href_list["action"])
		if("openLink")
			DIRECT_OUTPUT(src, link(href_list["link"]))

	if(hsrc)
		var/datum/real_src = hsrc
		if(QDELETED(real_src))
			return

	#ifdef NULL_CLIENT_BUG_CHECK
	if(QDELETED(usr))
		return
	#endif

	return ..()	//redirect to hsrc.Topic()


/client/New(TopicData)
	var/tdata = TopicData //save this for later use
	chatOutput = new /datum/chatOutput(src)
	TopicData = null	//Prevent calls to client.Topic from connect

	if(connection != "seeker" && connection != "web")	//Invalid connection type.
		return null

	GLOB.clients += src
	GLOB.directory[ckey] = src

	GLOB.ahelp_tickets.ClientLogin(src)

	if(CONFIG_GET(flag/localhost_rank))
		var/static/list/localhost_addresses = list("127.0.0.1", "::1")
		if(isnull(address) || (address in localhost_addresses))
			var/datum/admin_rank/rank = new("!localhost!", R_EVERYTHING, , R_EVERYTHING)
			var/datum/admins/admin = new(rank, ckey, TRUE)
			admin.associate(src)

	holder = GLOB.admin_datums[ckey]
	if(holder)
		GLOB.admins |= src
		holder.owner = src
		holder.activate()
	else if(GLOB.deadmins[ckey])
		verbs += /client/proc/readmin

	//preferences datum - also holds some persistant data for the client (because we may as well keep these datums to a minimum)
	prefs = GLOB.preferences_datums[ckey]
	if(!prefs || isnull(prefs) || !istype(prefs))
		prefs = new /datum/preferences(src)
		GLOB.preferences_datums[ckey] = prefs
	prefs.parent = src
	prefs.last_ip = address				//these are gonna be used for banning
	prefs.last_id = computer_id			//these are gonna be used for banning
	fps = prefs.clientfps

	var/full_version = "[byond_version].[byond_build ? byond_build : "xxx"]"
	log_access("Login: [key_name(src)] from [address ? address : "localhost"]-[computer_id] || BYOND v[full_version]")

	if(CONFIG_GET(flag/log_access))
		for(var/I in GLOB.clients)
			if(!I)
				stack_trace("null in GLOB.clients during client/New()")
				continue
			if(I == src)
				continue
			var/client/C = I
			if(C.key && (C.key != key) )
				var/matches
				if( (C.address == address) )
					matches += "IP ([address])"
				if( (C.computer_id == computer_id) )
					if(matches)
						matches += " and "
					matches += "ID ([computer_id])"
				if(matches)
					if(C)
						message_admins("<span class='danger'><B>Notice: </B></span><span class='notice'>[key_name_admin(src)] has the same [matches] as [key_name_admin(C)].</span>")
						log_access("Notice: [key_name(src)] has the same [matches] as [key_name(C)].")
					else
						message_admins("<span class='danger'><B>Notice: </B></span><span class='notice'>[key_name_admin(src)] has the same [matches] as [key_name_admin(C)] (no longer logged in). </span>")
						log_access("Notice: [key_name(src)] has the same [matches] as [key_name(C)] (no longer logged in).")

	if(GLOB.player_details[ckey])
		player_details = GLOB.player_details[ckey]
		player_details.byond_version = full_version
	else
		player_details = new
		player_details.byond_version = full_version
		GLOB.player_details[ckey] = player_details

	. = ..()	//calls mob.Login()
	if(length(GLOB.stickybanadminexemptions))
		GLOB.stickybanadminexemptions -= ckey
		if (!length(GLOB.stickybanadminexemptions))
			restore_stickybans()

	if(SSinput.initialized)
		set_macros()
		update_movement_keys()

	chatOutput.start() // Starts the chat

	if(byond_version < REQUIRED_CLIENT_MAJOR || (byond_build && byond_build < REQUIRED_CLIENT_MINOR))
		//to_chat(src, "<span class='userdanger'>Your version of byond is severely out of date.</span>")
		to_chat(src, "<span class='userdanger'>TGMC now requires the first stable [REQUIRED_CLIENT_MAJOR] build, please update your client to [REQUIRED_CLIENT_MAJOR].[MIN_RECOMMENDED_CLIENT].</span>")
		to_chat(src, "<span class='danger'>Please download a new version of byond. If [byond_build] is the latest, you can go to <a href=\"https://secure.byond.com/download/build\">BYOND's website</a> to download other versions.</span>")
		addtimer(CALLBACK(src, qdel(src), 2 SECONDS))
		return

	if(!byond_build || byond_build < 1386)
		message_admins("[key_name(src)] has been detected as spoofing their byond version. Connection rejected.")
		log_access("Failed Login: [key] - Spoofed byond version")
		qdel(src)
		return

	if(byond_build < MIN_RECOMMENDED_CLIENT)
		to_chat(src, "<span class='userdanger'>Your version of byond has known client crash issues, it's recommended you update your version.</span>")
		to_chat(src, "<span class='danger'>Please download a new version of byond. If [byond_build] is the latest, you can go to <a href=\"https://secure.byond.com/download/build\">BYOND's website</a> to download other versions.</span>")

	if(num2text(byond_build) in GLOB.blacklisted_builds)
		log_access("Failed login: [key] - blacklisted byond version")
		to_chat(src, "<span class='userdanger'>Your version of byond is blacklisted.</span>")
		to_chat(src, "<span class='danger'>Byond build [byond_build] ([byond_version].[byond_build]) has been blacklisted for the following reason: [GLOB.blacklisted_builds[num2text(byond_build)]].</span>")
		to_chat(src, "<span class='danger'>Please download a new version of byond. If [byond_build] is the latest, you can go to <a href=\"https://secure.byond.com/download/build\">BYOND's website</a> to download other versions.</span>")
		addtimer(CALLBACK(src, qdel(src), 2 SECONDS))
		return

	if(GLOB.custom_info)
		to_chat(src, "<h1 class='alert'>Custom Information</h1>")
		to_chat(src, "<h2 class='alert'>The following custom information has been set for this round:</h2>")
		to_chat(src, "<span class='alert'>[GLOB.custom_info]</span>")
		to_chat(src, "<br>")

	connection_time = world.time
	connection_realtime = world.realtime
	connection_timeofday = world.timeofday

	winset(src, null, "command=\".configure graphics-hwmode on\"")

	var/cached_player_age = set_client_age_from_db(tdata) //we have to cache this because other shit may change it and we need it's current value now down below.
	if(isnum(cached_player_age) && cached_player_age == -1) //first connection
		player_age = 0
	var/nnpa = CONFIG_GET(number/notify_new_player_age)
	if(isnum(cached_player_age) && cached_player_age == -1) //first connection
		if(nnpa >= 0)
			message_admins("New user: [key_name_admin(src)] is connecting here for the first time.")
	else if(isnum(cached_player_age) && cached_player_age < nnpa)
		message_admins("New user: [key_name_admin(src)] just connected with an age of [cached_player_age] day[(player_age == 1 ? "" : "s")]")
	if(CONFIG_GET(flag/use_account_age_for_jobs) && account_age >= 0)
		player_age = account_age
	if(account_age >= 0 && account_age < nnpa)
		message_admins("[key_name_admin(src)] (IP: [address], ID: [computer_id]) is a new BYOND account [account_age] day[(account_age == 1 ? "" : "s")] old, created on [account_join_date].")


	get_message_output("watchlist entry", ckey)
	validate_key_in_db()

	send_resources()

	generate_clickcatcher()
	apply_clickcatcher()

	if(prefs.lastchangelog != GLOB.changelog_hash) //bolds the changelog button on the interface so we know there are updates.
		to_chat(src, "<span class='info'>You have unread updates in the changelog.</span>")
		if(CONFIG_GET(flag/aggressive_changelog))
			changes()
		else
			winset(src, "infowindow.changelog", "font-style=bold")

	if(ckey in GLOB.clientmessages)
		for(var/message in GLOB.clientmessages[ckey])
			to_chat(src, message)
		GLOB.clientmessages.Remove(ckey)

	to_chat(src, get_message_output("message", ckey))

	if(holder)
		if(holder.rank.rights & R_ADMIN)
			message_admins("Admin login: [key_name_admin(src)].")
			to_chat(src, get_message_output("memo"))
		else if(holder.rank.rights & R_MENTOR)
			message_staff("Mentor login: [key_name_admin(src)].")

	var/list/topmenus = GLOB.menulist[/datum/verbs/menu]
	for(var/thing in topmenus)
		var/datum/verbs/menu/topmenu = thing
		var/topmenuname = "[topmenu]"
		if(topmenuname == "[topmenu.type]")
			var/list/tree = splittext(topmenuname, "/")
			topmenuname = tree[length(tree)]
		winset(src, "[topmenu.type]", "parent=menu;name=[url_encode(topmenuname)]")
		var/list/entries = topmenu.Generate_list(src)
		for(var/child in entries)
			winset(src, "[child]", "[entries[child]]")
			if(!ispath(child, /datum/verbs/menu))
				var/procpath/verbpath = child
				if(verbpath.name[1] != "@")
					new child(src)

	for(var/thing in prefs.menuoptions)
		var/datum/verbs/menu/menuitem = GLOB.menulist[thing]
		if(menuitem)
			menuitem.Load_checked(src)


	//This is down here because of the browse() calls in tooltip/New()
	if(!tooltips && prefs.tooltips)
		tooltips = new /datum/tooltip(src)


	winset(src, null, "mainwindow.title='[CONFIG_GET(string/title)]'")

	Master.UpdateTickRate()



//////////////////
//  DISCONNECT  //
//////////////////
/client/Del()
	SEND_SIGNAL(src, COMSIG_CLIENT_DISCONNECTED)
	log_access("Logout: [key_name(src)]")
	if(holder)
		if(check_rights(R_ADMIN, FALSE))
			message_admins("Admin logout: [key_name(src)].")
		else if(check_rights(R_MENTOR, FALSE))
			message_staff("Mentor logout: [key_name(src)].")
		holder.owner = null
		GLOB.admins -= src

	GLOB.ahelp_tickets.ClientLogout(src)
	GLOB.directory -= ckey
	GLOB.clients -= src
	seen_messages = null
	QDEL_LIST_ASSOC_VAL(char_render_holders)
	Master.UpdateTickRate()
	return ..()


/client/Destroy()
	. = ..() //Even though we're going to be hard deleted there are still some things that want to know the destroy is happening
	return QDEL_HINT_HARDDEL_NOW

/client/Click(atom/object, atom/location, control, params)
	if(!control)
		return
	if(click_intercepted)
		if(click_intercepted >= world.time)
			click_intercepted = 0 //Reset and return. Next click should work, but not this one.
			return
		click_intercepted = 0 //Just reset. Let's not keep re-checking forever.
	var/ab = FALSE
	var/list/L = params2list(params)

	var/dragged = L["drag"]
	if(dragged && !L[dragged])
		return

	if(object && object == middragatom && L["left"])
		ab = max(0, 5 SECONDS - (world.time - middragtime) * 0.1)

	var/mcl = CONFIG_GET(number/minute_click_limit)
	if(mcl && !check_rights(R_ADMIN, FALSE))
		var/minute = round(world.time, 600)
		if(!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)
		if(minute != clicklimiter[CURRENT_MINUTE])
			clicklimiter[CURRENT_MINUTE] = minute
			clicklimiter[MINUTE_COUNT] = 0
		clicklimiter[MINUTE_COUNT] += 1+(ab)
		if(clicklimiter[MINUTE_COUNT] > mcl)
			var/msg = "Your previous click was ignored because you've done too many in a minute."
			if(minute != clicklimiter[ADMINSWARNED_AT]) //only one admin message per-minute. (if they spam the admins can just boot/ban them)
				clicklimiter[ADMINSWARNED_AT] = minute
				log_admin_private("[key_name(src)] has hit the per-minute click limit of [mcl].")
				message_admins("[ADMIN_TPMONTY(mob)] has hit the per-minute click limit of [mcl].")
				if(ab)
					log_admin_private("[key_name(src)] is likely using the middle click aimbot exploit.")
					message_admins("[ADMIN_TPMONTY(mob)] is likely using the middle click aimbot exploit.")
			to_chat(src, "<span class='danger'>[msg]</span>")
			return

	var/scl = CONFIG_GET(number/second_click_limit)
	if(scl && !check_rights(R_ADMIN, FALSE))
		var/second = round(world.time, 10)
		if(!clicklimiter)
			clicklimiter = new(LIMITER_SIZE)
		if(second != clicklimiter[CURRENT_SECOND])
			clicklimiter[CURRENT_SECOND] = second
			clicklimiter[SECOND_COUNT] = 0
		clicklimiter[SECOND_COUNT] += 1+(!!ab)
		if(clicklimiter[SECOND_COUNT] > scl)
			to_chat(src, "<span class='danger'>Your previous click was ignored because you've done too many in a second</span>")
			return

//Hijack for FC.
	if(prefs.focus_chat)
		winset(src, null, "input.focus=true")

	return ..()

//checks if a client is afk
//3000 frames = 5 minutes
/client/proc/is_afk(duration = 5 MINUTES)
	if(inactivity > duration)
		return inactivity
	return FALSE


/// Send resources to the client. Sends both game resources and browser assets.
/client/proc/send_resources()
#if (PRELOAD_RSC == 0)
	var/static/next_external_rsc = 0
	var/list/external_rsc_urls = CONFIG_GET(keyed_list/external_rsc_urls)
	if(length(external_rsc_urls))
		next_external_rsc = WRAP(next_external_rsc+1, 1, external_rsc_urls.len+1)
		preload_rsc = external_rsc_urls[next_external_rsc]
#endif

	spawn (10) //removing this spawn causes all clients to not get verbs.

		//load info on what assets the client has
		src << browse('code/modules/asset_cache/validate_assets.html', "window=asset_cache_browser")

		//Precache the client with all other assets slowly, so as to not block other browse() calls
		if (CONFIG_GET(flag/asset_simple_preload))
			addtimer(CALLBACK(SSassets.transport, /datum/asset_transport.proc/send_assets_slow, src, SSassets.transport.preload), 5 SECONDS)


//Hook, override it to run code when dir changes
//Like for /atoms, but clients are their own snowflake FUCK
/client/proc/setDir(newdir)
	dir = newdir


/client/proc/show_character_previews(mutable_appearance/MA)
	var/pos = 0
	for(var/D in GLOB.cardinals)
		pos++
		var/obj/screen/O = LAZYACCESS(char_render_holders, "[D]")
		if(!O)
			O = new
			LAZYSET(char_render_holders, "[D]", O)
			screen |= O
		O.appearance = MA
		O.dir = D
		O.screen_loc = "character_preview_map:0,[pos]"


/client/proc/clear_character_previews()
	for(var/index in char_render_holders)
		var/obj/screen/S = char_render_holders[index]
		screen -= S
		qdel(S)
	char_render_holders = null


/client/proc/set_client_age_from_db(connectiontopic)
	if(IsGuestKey(key))
		return
	if(!SSdbcore.Connect())
		return
	var/sql_ckey = sanitizeSQL(ckey)
	var/datum/DBQuery/query_get_related_ip = SSdbcore.NewQuery("SELECT ckey FROM [format_table_name("player")] WHERE ip = INET_ATON('[address]') AND ckey != '[sql_ckey]'")
	if(!query_get_related_ip.Execute())
		qdel(query_get_related_ip)
		return
	related_accounts_ip = ""
	while(query_get_related_ip.NextRow())
		related_accounts_ip += "[query_get_related_ip.item[1]], "
	qdel(query_get_related_ip)
	var/datum/DBQuery/query_get_related_cid = SSdbcore.NewQuery("SELECT ckey FROM [format_table_name("player")] WHERE computerid = '[computer_id]' AND ckey != '[sql_ckey]'")
	if(!query_get_related_cid.Execute())
		qdel(query_get_related_cid)
		return
	related_accounts_cid = ""
	while (query_get_related_cid.NextRow())
		related_accounts_cid += "[query_get_related_cid.item[1]], "
	qdel(query_get_related_cid)
	var/admin_rank = "Player"
	if(holder && holder.rank)
		admin_rank = holder.rank.name
	var/sql_ip = sanitizeSQL(address)
	var/sql_computerid = sanitizeSQL(computer_id)
	var/sql_admin_rank = sanitizeSQL(admin_rank)
	var/new_player
	var/datum/DBQuery/query_client_in_db = SSdbcore.NewQuery("SELECT 1 FROM [format_table_name("player")] WHERE ckey = '[sql_ckey]'")
	if(!query_client_in_db.Execute())
		qdel(query_client_in_db)
		return
	if(!query_client_in_db.NextRow())
		if(CONFIG_GET(flag/panic_bunker) && !(holder?.rank?.rights & R_ADMIN) && !GLOB.deadmins[ckey])
			log_access("Failed Login: [key] - New account attempting to connect during panic bunker")
			message_admins("<span class='adminnotice'>Failed Login: [key] - New account attempting to connect during panic bunker.</span>")
			to_chat(src, CONFIG_GET(string/panic_bunker_message))
			var/list/connectiontopic_a = params2list(connectiontopic)
			var/list/panic_addr = CONFIG_GET(string/panic_server_address)
			if(panic_addr && !connectiontopic_a["redirect"])
				var/panic_name = CONFIG_GET(string/panic_server_name)
				to_chat(src, "<span class='notice'>Sending you to [panic_name ? panic_name : panic_addr].</span>")
				winset(src, null, "command=.options")
				DIRECT_OUTPUT(src, link("[panic_addr]?redirect=1"))
			qdel(query_client_in_db)
			qdel(src)
			return

		new_player = 1
		account_join_date = sanitizeSQL(findJoinDate())
		var/sql_key = sanitizeSQL(key)
		var/datum/DBQuery/query_add_player = SSdbcore.NewQuery("INSERT INTO [format_table_name("player")] (`ckey`, `byond_key`, `firstseen`, `firstseen_round_id`, `lastseen`, `lastseen_round_id`, `ip`, `computerid`, `lastadminrank`, `accountjoindate`) VALUES ('[sql_ckey]', '[sql_key]', Now(), '[GLOB.round_id]', Now(), '[GLOB.round_id]', INET_ATON('[sql_ip]'), '[sql_computerid]', '[sql_admin_rank]', [account_join_date ? "'[account_join_date]'" : "NULL"])")
		if(!query_add_player.Execute())
			qdel(query_client_in_db)
			qdel(query_add_player)
			return
		qdel(query_add_player)
		if(!account_join_date)
			account_join_date = "Error"
			account_age = -1
	qdel(query_client_in_db)
	var/datum/DBQuery/query_get_client_age = SSdbcore.NewQuery("SELECT firstseen, DATEDIFF(Now(),firstseen), accountjoindate, DATEDIFF(Now(),accountjoindate) FROM [format_table_name("player")] WHERE ckey = '[sql_ckey]'")
	if(!query_get_client_age.Execute())
		qdel(query_get_client_age)
		return
	if(query_get_client_age.NextRow())
		player_join_date = query_get_client_age.item[1]
		player_age = text2num(query_get_client_age.item[2])
		if(!account_join_date)
			account_join_date = query_get_client_age.item[3]
			account_age = text2num(query_get_client_age.item[4])
			if(!account_age)
				account_join_date = sanitizeSQL(findJoinDate())
				if(!account_join_date)
					account_age = -1
				else
					var/datum/DBQuery/query_datediff = SSdbcore.NewQuery("SELECT DATEDIFF(Now(),'[account_join_date]')")
					if(!query_datediff.Execute())
						qdel(query_datediff)
						return
					if(query_datediff.NextRow())
						account_age = text2num(query_datediff.item[1])
					qdel(query_datediff)
	qdel(query_get_client_age)
	if(!new_player)
		var/datum/DBQuery/query_log_player = SSdbcore.NewQuery("UPDATE [format_table_name("player")] SET lastseen = Now(), lastseen_round_id = '[GLOB.round_id]', ip = INET_ATON('[sql_ip]'), computerid = '[sql_computerid]', lastadminrank = '[sql_admin_rank]', accountjoindate = [account_join_date ? "'[account_join_date]'" : "NULL"] WHERE ckey = '[sql_ckey]'")
		if(!query_log_player.Execute())
			qdel(query_log_player)
			return
		qdel(query_log_player)
	if(!account_join_date)
		account_join_date = "Error"
	var/datum/DBQuery/query_log_connection = SSdbcore.NewQuery("INSERT INTO `[format_table_name("connection_log")]` (`id`,`datetime`,`server_ip`,`server_port`,`round_id`,`ckey`,`ip`,`computerid`) VALUES(null,Now(),INET_ATON(IF('[world.internet_address]' LIKE '', '0', '[world.internet_address]')),'[world.port]','[GLOB.round_id]','[sql_ckey]',INET_ATON('[sql_ip]'),'[sql_computerid]')")
	query_log_connection.Execute()
	qdel(query_log_connection)
	if(new_player)
		player_age = -1
	. = player_age


/client/proc/findJoinDate()
	var/list/http = world.Export("http://byond.com/members/[ckey]?format=text")
	if(!http)
		log_world("Failed to connect to byond member page to age check [ckey]")
		return
	var/F = file2text(http["CONTENT"])
	if(F)
		var/regex/R = regex("joined = \"(\\d{4}-\\d{2}-\\d{2})\"")
		if(R.Find(F))
			. = R.group[1]
		else
			CRASH("Age check regex failed for [src.ckey]")


/client/proc/validate_key_in_db()
	var/sql_ckey = sanitizeSQL(ckey)
	var/sql_key
	var/datum/DBQuery/query_check_byond_key = SSdbcore.NewQuery("SELECT byond_key FROM [format_table_name("player")] WHERE ckey = '[sql_ckey]'")
	if(!query_check_byond_key.Execute())
		qdel(query_check_byond_key)
		return
	if(query_check_byond_key.NextRow())
		sql_key = query_check_byond_key.item[1]
	qdel(query_check_byond_key)
	if(key != sql_key)
		var/list/http = world.Export("http://byond.com/members/[ckey]?format=text")
		if(!http)
			log_world("Failed to connect to byond member page to get changed key for [ckey]")
			return
		var/F = file2text(http["CONTENT"])
		if(F)
			var/regex/R = regex("\\tkey = \"(.+)\"")
			if(R.Find(F))
				var/web_key = sanitizeSQL(R.group[1])
				var/datum/DBQuery/query_update_byond_key = SSdbcore.NewQuery("UPDATE [format_table_name("player")] SET byond_key = '[web_key]' WHERE ckey = '[sql_ckey]'")
				query_update_byond_key.Execute()
				qdel(query_update_byond_key)
			else
				CRASH("Key check regex failed for [ckey]")


/client/proc/rescale_view(change, min, max)
	var/viewscale = getviewsize(view)
	var/x = viewscale[1]
	var/y = viewscale[2]
	x = clamp(x + change, min, max)
	y = clamp(y + change, min,max)
	change_view("[x]x[y]")


/client/proc/update_movement_keys(datum/preferences/direct_prefs)
	var/datum/preferences/D = prefs || direct_prefs
	if(!D?.key_bindings)
		return
	movement_keys = list()
	for(var/key in D.key_bindings)
		for(var/kb_name in D.key_bindings[key])
			switch(kb_name)
				if("North")
					movement_keys[key] = NORTH
				if("East")
					movement_keys[key] = EAST
				if("West")
					movement_keys[key] = WEST
				if("South")
					movement_keys[key] = SOUTH


/client/proc/change_view(new_size)
	if(isnull(new_size))
		CRASH("change_view called without argument.")
	if(isnum(new_size))
		CRASH("change_view called with a number argument. Use the string format instead.")
	view = new_size
	apply_clickcatcher()
	mob.reload_fullscreens()
	if(prefs.auto_fit_viewport)
		addtimer(CALLBACK(src, .verb/fit_viewport, 1 SECONDS)) //Delayed to avoid wingets from Login calls.


/client/proc/generate_clickcatcher()
	if(void)
		return
	void = new()
	screen += void


/client/proc/apply_clickcatcher()
	generate_clickcatcher()
	var/list/actualview = getviewsize(view)
	void.UpdateGreed(actualview[1], actualview[2])


//This stops files larger than UPLOAD_LIMIT being sent from client to server via input(), client.Import() etc.
/client/AllowUpload(filename, filelength)
	if(!check_rights(R_ADMIN, FALSE) && filelength > UPLOAD_LIMIT)
		to_chat(src, "<font color='red'>Error: AllowUpload(): File Upload too large. Upload Limit: [UPLOAD_LIMIT/1024]KiB.</font>")
		return FALSE
	else if(filelength > UPLOAD_LIMIT_ADMIN)
		to_chat(src, "<font color='red'>Error: AllowUpload(): File Upload too large. Upload Limit: [UPLOAD_LIMIT/1024]KiB. Stop trying to break the server.</font>")
		return FALSE
	return TRUE


GLOBAL_VAR_INIT(automute_on, null)
/client/proc/handle_spam_prevention(message, mute_type)
	//Performance
	if(isnull(GLOB.automute_on))
		GLOB.automute_on = CONFIG_GET(flag/automute_on)

	total_message_count += 1

	var/weight = SPAM_TRIGGER_WEIGHT_FORMULA(message)
	total_message_weight += weight

	var/message_cache = total_message_count
	var/weight_cache = total_message_weight

	if(last_message_time && world.time > last_message_time)
		last_message_time = 0
		total_message_count = 0
		total_message_weight = 0

	else if(!last_message_time)
		last_message_time = world.time + SPAM_TRIGGER_TIME_PERIOD

	last_message = message

	var/mute = message_cache >= SPAM_TRIGGER_AUTOMUTE || (weight_cache > SPAM_TRIGGER_WEIGHT_AUTOMUTE && message_cache != 1)
	var/warning = message_cache >= SPAM_TRIGGER_WARNING || (weight_cache > SPAM_TRIGGER_WEIGHT_WARNING && message_cache != 1)

	if(mute)
		if(GLOB.automute_on && !check_rights(R_ADMIN, FALSE))
			to_chat(src, "<span class='danger'>You have exceeded the spam filter. An auto-mute was applied.</span>")
			create_message("note", ckey(key), "SYSTEM", "Automuted due to spam. Last message: '[last_message]'", null, null, FALSE, FALSE, null, FALSE, "Minor")
			mute(src, mute_type, TRUE)
		return TRUE

	if(warning && GLOB.automute_on && !check_rights(R_ADMIN, FALSE))
		to_chat(src, "<span class='danger'>You are nearing the spam filter limit.</span>")

/client/vv_edit_var(var_name, var_value)
	switch(var_name)
		if("holder")
			return FALSE
		if("ckey")
			return FALSE
		if("key")
			return FALSE
		if("view")
			change_view(var_value)
			return TRUE
	return ..()
