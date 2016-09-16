#################################################
#
#            HOMER & OpenSIPs
#
#################################################

log_level=3
log_stderror=no
log_facility=LOG_LOCAL0

children=4

listen=hep_udp:0.0.0.0:LISTEN_PORT


### CHANGEME path to your opensips modules here 
mpath="/usr/lib/x86_64-linux-gnu/opensips/modules/"

loadmodule "cfgutils.so"
loadmodule "signaling.so"
loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "maxfwd.so"
loadmodule "sipmsgops.so"
loadmodule "mi_fifo.so"
loadmodule "uri.so"
loadmodule "db_mysql.so"
loadmodule "sipcapture.so"
loadmodule "proto_hep.so"
loadmodule "cachedb_local.so"
loadmodule "avpops.so"
loadmodule "mmgeoip.so"
loadmodule "exec.so"
loadmodule "json.so"

#settings

### CHANGEME hep interface
# should be loaded After proto_hep

#Cache
modparam("cachedb_local", "cache_table_size", 10)
modparam("cachedb_local", "cache_clean_period", 600)

modparam("tm", "fr_timeout", 2)
modparam("tm", "fr_inv_timeout", 3)
modparam("tm", "restart_fr_on_each_reply", 0)
modparam("tm", "onreply_avp_mode", 1)

#### Record Route Module
/* do not append from tag to the RR (no need for this script) */
modparam("rr", "append_fromtag", 0)

#### FIFO Management Interface

modparam("mi_fifo", "fifo_name", "/tmp/opensips_fifo")
modparam("mi_fifo", "fifo_mode", 0666)

#### SIP MSG OPerationS module
#### URI module
#### MAX ForWarD module

modparam("uri", "use_uri_table", 0)

### CHANGEME mysql uri here if you do sip_capture()
modparam("sipcapture", "db_url", "mysql://DB_USER:DB_PASS@DB_HOST/homer_data")
modparam("sipcapture", "capture_on", 1)
modparam("sipcapture", "hep_capture_on", 1)
modparam("sipcapture", "hep_route", "my_hep_route")


### hep version here 1, 2 or 3
#modparam("proto_hep", "hep_version", 3)

#
modparam("avpops","db_url","mysql://DB_USER:DB_PASS@DB_HOST/homer_statistic")


modparam("mmgeoip", "mmgeoip_city_db_path", "/usr/share/GeoIP/GeoIP.dat")


route{

	cache_add("local", "a=>method::total", 1, 320);
	cache_add("local", "a=>packet::count", 1, 320);
	cache_add("local", "a=>packet::size", $ml, 320);
	
	if(cache_fetch("local","b=>$rm::$cs::$ci",$var(tmpvar))) {
		xlog("TEST: $var(tmpvar)\n");
		route(STORE);
		exit;
	}
	
	cache_add("local", "b=>$rm::$cs::$ci", 1, 320);
	cache_add("local", "a=>method::all", 1, 320);


	if (is_method("INVITE|REGISTER")) {

		if($ua =~ "(friendly-scanner|sipvicious|sipcli)") {
			avp_db_query("INSERT INTO alarm_data_mem (create_date, type, total, source_ip, description) VALUES(NOW(), 'scanner', 1, '$si', 'Friendly scanner alarm!') ON DUPLICATE KEY UPDATE total=total+1");
			route(KILL_VICIOUS);
		}

		#IP Method
		avp_db_query("INSERT INTO stats_ip_mem ( method, source_ip, total) VALUES('$rm', '$si', 1) ON DUPLICATE KEY UPDATE total=total+1");

		#GEO
		if(mmg_lookup("lon:lat","$si","$avp(lat_lon)")) {
			avp_db_query("INSERT INTO stats_geo_mem ( method, country, lat, lon, total) VALUES('$rm', '$(avp(lat_lon)[3])', '$(avp(lat_lon)[0])', '$(avp(lat_lon)[1])', 1) ON DUPLICATE KEY UPDATE total=total+1");
		};


		if (is_method("INVITE")) {			

		        if (has_totag()) {
			        cache_add("local", "a=>method::reinvite", 1, 320);
			}
			else {
			        cache_add("local", "a=>method::invite", 1, 320);
				if($adu != "") {
				        cache_add("local", "a=>method::invite::auth", 1, 320);
				}

				if($ua != "") {
					avp_db_query("INSERT INTO stats_useragent_mem (useragent, method, total) VALUES('$ua', 'INVITE', 1) ON DUPLICATE KEY UPDATE total=total+1");
				}

			}					
		}
		else {
			cache_add("local", "a=>method::register", 1, 320);

			if($adu != "") {
				cache_add("local", "a=>method::register::auth", 1, 320);
			}
			
			if($ua != "") {
				avp_db_query("INSERT INTO stats_useragent_mem (useragent, method, total) VALUES('$ua', 'REGISTER', 1) ON DUPLICATE KEY UPDATE total=total+1");
			}
		}
	}

	else if(is_method("BYE")) {
	
		cache_add("local", "a=>method::bye", 1, 320);

		if(is_present_hf("Reason")) {
                       $var(cause) = $(hdr(Reason){param.value,cause}{s.int});
                       if($var(cause) != 16 && $var(cause) !=17) {
				cache_add("local", "a=>stats::sdf", 1, 320);
		       }
		}

	}
	else if(is_method("CANCEL")) {
		cache_add("local", "a=>method::cancel", 1, 320);
	}
	else if(is_method("OPTIONS")) {
		cache_add("local", "a=>method::options", 1, 320);
	}
	else if(is_method("REFER")) {
		cache_add("local", "a=>method::refer", 1, 320);
	}
	else if(is_method("UPDATE")) {
		cache_add("local", "a=>method::update", 1, 320);
	}	
	else if(is_method("PUBLISH"))
        {
                if(has_body("application/vq-rtcpxr") && $(rb{s.substr,0,1}) != "x") {
                        $var(table) = "report_capture";
			$var(reg) = "/.*CallID:((\d|\-|\w|\@){5,120}).*$/\1/s";
                        $var(callid) = $(rb{re.subst,$var(reg)});			
			#Local IP. Only for stats
			xlog("PUBLISH: $var(callid)\n");
			report_capture("report_capture", "$var(callid)", "1");
                        drop;
                }
        }
	
	else if(is_method("ACK")) {
		cache_add("local", "a=>method::ack", 1, 320);
        }
        else {
		cache_add("local", "a=>method::unknown", 1, 320);
        }     

	#Store
	route(STORE);
	exit;

}

onreply_route {

	cache_add("local", "a=>method::total", 1, 320);

	if(cache_fetch("local","b=>$rs::$cs::$rm::$ci",$var(tmpvar))) {
		xlog("TEST: $var(tmpvar)\n");
		route(STORE);
		exit;
	}
	
	cache_add("local", "b=>$rs::$cs::$rm::$ci", 1, 320);
	cache_add("local", "a=>method::all", 1, 320);

	#413 Too large
	if(status == "413") {	
		cache_add("local", "a=>response::413", 1, 320);
                cache_add("local", "a=>alarm::413", 1, 320);
	}
	#403 Unauthorize
        else if(status == "403") {
		cache_add("local", "a=>response::403", 1, 320);
                cache_add("local", "a=>alarm::403", 1, 320);
        }
	# Too many hops
	else if(status == "483") {	
		cache_add("local", "a=>response::483", 1, 320);
                cache_add("local", "a=>alarm::483", 1, 320);
	}
	# loops
	else if(status == "482") {	
		cache_add("local", "a=>response::482", 1, 320);
                cache_add("local", "a=>alarm::482", 1, 320);
	}
	# Call Transaction Does not exist
	else if(status == "481") {	
                cache_add("local", "a=>alarm::481", 1, 320);
	}
	# 408 Timeout
	else if(status == "408") {	
                cache_add("local", "a=>alarm::408", 1, 320);
	}
	# 400
	else if(status == "400") {	
                cache_add("local", "a=>alarm::400", 1, 320);
	}
	# MOVED
	else if(status =~ "^(30[012])$") {	
                cache_add("local", "a=>response::300", 1, 320);
	}

	if($rm == "INVITE") {
		#ISA
		if(status =~ "^(408|50[03])$") {	
	                cache_add("local", "a=>stats::isa", 1, 320);
		}
		#Bad486
		if(status =~ "^(486|487|603)$") {	
	                cache_add("local", "a=>stats::bad::invite", 1, 320);
		}

		#SD
		if(status =~ "^(50[034])$") {	
	                cache_add("local", "a=>stats::sd", 1, 320);
		}

		if(status == "407") {	
	                cache_add("local", "a=>response::407::invite", 1, 320);
		}
		else if(status == "401") {			
	                cache_add("local", "a=>response::401::invite", 1, 320);
		}
		else if(status == "200") {			
	                cache_add("local", "a=>response::200::invite", 1, 320);
		}
		#Aditional stats
	        else if(status == "100") {
	                cache_add("local", "a=>response::100::invite", 1, 320);
                }
                else if(status == "180") {
	                cache_add("local", "a=>response::180::invite", 1, 320);
                }   
                else if(status == "183") {                      
	                cache_add("local", "a=>response::183::invite", 1, 320);
                }
	}
	else if($rm == "BYE") {

		if(status == "407") {	
	                cache_add("local", "a=>response::407::bye", 1, 320);
		}
		else if(status == "401") {			
	                cache_add("local", "a=>response::401::bye", 1, 320);
		}
		else if(status == "200") {			
	                cache_add("local", "a=>response::200::bye", 1, 320);
		}
	}
	
	#Store
	route(STORE);
	drop;
}

route[KILL_VICIOUS] {
	xlog("Kill-Vicious ! si : $si ru : $ru ua : $ua\n");
	return;
}



timer_route[stats_alarms_update, 60] {

    #xlog("timer routine: time is $Ts\n");
    route(CHECK_ALARM);
    #Check statistics 	 
    route(CHECK_STATS);

}

route[SEND_ALARM] {
   	exec('echo "Value: $var(thvalue), Type: $var(atype), Desc: $var(aname)" | mail -s "Homer Alarm $var(atype) - $var(thvalue)" $var(aemail) ') ;
}

route[CHECK_ALARM] 
{

    #POPULATE ALARM THRESHOLDS
    #Homer 5 sql schema    
    avp_db_query("SELECT type,value,name,notify,email FROM alarm_config WHERE NOW() between startdate AND stopdate AND active = 1", "$avp(type);$avp(value);$avp(name);$avp(notify);$avp(email)");
    $var(i) = 0;
    while ( $(avp(type)[$var(i)]) != NULL ) 
    {
	$var(atype) = $(avp(type)[$var(i)]);
        $var(avalue) = $(avp(value)[$var(i)]);
        $var(aname) = $(avp(name)[$var(i)]);
        $var(anotify) = $(avp(notify)[$var(i)]);
        $var(aemail) = $(avp(email)[$var(i)]);
        $avp($var(atype)) = $var(avalue);

	$var(anotify) = $(var(anotify){s.int});

	if(cache_fetch("local","a=>alarm::$var(atype)",$var(thvalue))) {

                cache_remove("local","a=>alarm::var(atype)");

                #If Alarm - go here
                if($var(thvalue) > $var(avalue)) {
                                                  
                        avp_db_query("INSERT INTO alarm_data (create_date, type, total, description) VALUES(NOW(), '$var(aname)', $var(thvalue), '$var(aname) - $var(atype)');");
                        #Notify
                        if($var(anotify) == 1) {
                                route(SEND_ALARM);
                        }                         
                }

                #Alarm for Scanner;
                if($var(atype) == "scanner") {
                        avp_db_query("DELETE FROM alarm_data_mem WHERE type='scanner' AND total < $var(avalue)");
                        if($var(anotify) == 1) 
                        {
                                avp_db_query("SELECT * FROM alarm_data_mem WHERE type='scanner' AND total  >= $var(avalue) LIMIT 2", "$avp(as)");        
                                if($(avp(as){s.int}) > 0) {
                                        route(SEND_ALARM);
                                }
                        }
                }
        }

	$var(i) = $var(i) + 1;
    }

    avp_db_query("DELETE FROM alarm_data WHERE create_date < DATE_SUB(NOW(), INTERVAL 5 DAY)");
}


route[CHECK_STATS] {	

	#xlog("TIMER UPDATE\n");
	#SQL STATS

	$var(interval) = 5;
	$var(tz) = $ctime(min);
	$var(tm) = ($ctime(min) % 10);

	#xlog("TIMER MIN: $var(tz) $var(tm)\n");

	if($var(tm) != 0 && $var(tm) != $var(interval)) return;

	#xlog("TIMER IN: $var(tz)  $var(tm)\n");

	$var(t1) = $Ts;
	$var(t2) = $var(t1) - (30*60);

	$var(t_date) = "FROM_UNIXTIME(" + $var(t1) + ", '%Y-%m-%d %H:%i:00')";
	$var(f_date) = "FROM_UNIXTIME(" + $var(t2) + ", '%Y-%m-%d %H:%i:00')";

	#ALARM SCANNERS
	avp_db_query("INSERT INTO alarm_data (create_date, type, total, source_ip, description) SELECT create_date, type, total, source_ip, description FROM alarm_data_mem;");
	avp_db_query("TRUNCATE TABLE alarm_data_mem");

	#STATS Useragent
	avp_db_query("INSERT INTO stats_useragent (from_date, to_date, useragent, method, total) SELECT $var(f_date) as from_date, $var(t_date) as to_date, useragent, method, total FROM stats_useragent_mem;");
	avp_db_query("TRUNCATE TABLE stats_useragent_mem");

	#STATS IP
	avp_db_query("INSERT INTO stats_ip (from_date, to_date, method, source_ip, total) SELECT $var(f_date) as from_date, $var(t_date) as to_date, method, source_ip, total FROM stats_ip_mem;");
	avp_db_query("TRUNCATE TABLE stats_ip_mem");

	avp_db_query("INSERT INTO stats_geo (from_date, to_date, method, country, lat, lon, total) SELECT $var(f_date) as from_date, $var(t_date) as to_date, method, country, lat, lon, total FROM stats_geo_mem;");
	avp_db_query("TRUNCATE TABLE stats_geo_mem");

	#INSERT SQL STATS
	#Packet HEP stats
	if(cache_fetch("local","a=>packet::count",$var(tmpvar))) {
		cache_remove("local","a=>packet::count");
        	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'packet_count', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}
	if(cache_fetch("local","a=>packet::size",$var(tmpvar))) {
		cache_remove("local","a=>packet::size");
        	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'packet_size', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}
	#SDF
	if(cache_fetch("local","a=>stats::sdf",$var(tmpvar))) {
                cache_remove("local","a=>stats::sdf");
	        avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'sdf', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}
	
	#ISA
	if(cache_fetch("local","a=>stats::isa",$var(tmpvar))) {
                cache_remove("local","a=>stats::isa");
		avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'isa', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#SD
	if(cache_fetch("local","a=>stats::sd",$var(tmpvar))) {
                cache_remove("local","a=>stats::sd");
        	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'isa', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#SSR
	if(cache_fetch("local","a=>stats::ssr",$var(tmpvar))) {
                cache_remove("local","a=>stats::ssr");
        	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'ssr', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}


	#ASR
	$var(asr) = 0;
	$var(ner) = 0;
	if(cache_fetch("local","a=>method::invite",$var(invite)))
	{
		$var(invite) = $(var(invite){s.int});

		if($var(invite) > 0) 
		{
			if(!cache_fetch("local","a=>response::407::invite",$var(invite407))) $var(invite407) = 0;
			if(!cache_fetch("local","a=>response::200::invite",$var(invite200))) $var(invite200) = 0;
			if(!cache_fetch("local","a=>response::bad::invite",$var(invitebad))) $var(invitebad) = 0;

			$var(invite407) = $(var(invite407){s.int});
			$var(invite200) = $(var(invite200){s.int});
			$var(invitebad) = $(var(invitebad){s.int});


        		$var(d) = $var(invite) - $var(invite407);
		        if($var(d) > 0) {
        		        $var(asr) =  $var(invite200) * 100 / $var(d);
                		if($var(asr) > 100)  $var(asr) = 100;
				$var(ner) = ($var(invite200) + $var(invitebad)) * 100 / $var(d);
		                if($var(ner) > 100)  $var(ner) = 100;
		        }
		}
	}

	#Stats DATA
	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'asr', $var(asr)) ON DUPLICATE KEY UPDATE total=(total+$var(asr))/2");
	avp_db_query("INSERT INTO stats_data (from_date, to_date, type, total) VALUES($var(f_date), $var(t_date), 'ner', $var(ner)) ON DUPLICATE KEY UPDATE total=(total+$var(ner))/2");

	#INVITE
	if(cache_fetch("local","a=>method::reinvite",$var(tmpvar))) {
		cache_remove("local","a=>method::reinvite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, totag, total) VALUES($var(f_date), $var(t_date),'INVITE', 1, $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#INVITE
	if(cache_fetch("local","a=>method::invite",$var(tmpvar))) {
		cache_remove("local","a=>method::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#INVITE AUTH
	if(cache_fetch("local","a=>method::invite::auth",$var(tmpvar))) {
		cache_remove("local","a=>method::invite::auth");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, auth, total) VALUES($var(f_date), $var(t_date), 'INVITE', 1, $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#REGISTER
	if(cache_fetch("local","a=>method::register",$var(tmpvar))) {
		cache_remove("local","a=>method::register");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'REGISTER', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}	

	#REGISTER AUTH
	if(cache_fetch("local","a=>method::register::auth",$var(tmpvar))) {
		cache_remove("local","a=>method::register::auth");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, auth, total) VALUES($var(f_date), $var(t_date), 'REGISTER', 1, $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}	

	#BYE
	if(cache_fetch("local","a=>method::bye",$var(tmpvar))) {
		cache_remove("local","a=>method::bye");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'BYE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#CANCEL
	if(cache_fetch("local","a=>method::cancel",$var(tmpvar))) {
		cache_remove("local","a=>method::cancel");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'CANCEL', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#OPTIONS
	if(cache_fetch("local","a=>method::options",$var(tmpvar))) {
		cache_remove("local","a=>method::options");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'OPTIONS', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	if(cache_fetch("local","a=>method::unknown",$var(tmpvar))) {
		cache_remove("local","a=>method::unknown");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'UNKNOWN', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}
    
	#ACK
	if(cache_fetch("local","a=>method::ack",$var(tmpvar))) {
		cache_remove("local","a=>method::ack");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'ACK', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}	

	#REFER
	if(cache_fetch("local","a=>method::refer",$var(tmpvar))) {
		cache_remove("local","a=>method::refer");
        	avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'REFER', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#UPDATE
	if(cache_fetch("local","a=>method::update",$var(tmpvar))) {
		cache_remove("local","a=>method::update");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'UPDATE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#RESPONSE
	#300
	if(cache_fetch("local","a=>response::300",$var(tmpvar))) {
		cache_remove("local","a=>response::300");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), '300', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#407 INVITE
	if(cache_fetch("local","a=>response::407::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::407::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '407', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#401 INVITE
	if(cache_fetch("local","a=>response::401::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::401::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '401', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#100 INVITE
	if(cache_fetch("local","a=>response::100::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::100::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '100', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}	

	#180 INVITE
	if(cache_fetch("local","a=>response::401::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::401::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '180', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#183 INVITE
	if(cache_fetch("local","a=>response::183::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::183::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '183', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#200 INVITE
	if(cache_fetch("local","a=>response::200::invite",$var(tmpvar))) {
		cache_remove("local","a=>response::200::invite");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '200', 'INVITE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#407 BYE
	if(cache_fetch("local","a=>response::407::bye",$var(tmpvar))) {
		cache_remove("local","a=>response::407::bye");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '407', 'BYE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#401 BYE
	if(cache_fetch("local","a=>response::401::bye",$var(tmpvar))) {
		cache_remove("local","a=>response::401::bye");
        	avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '401', 'BYE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#200 BYE
	if(cache_fetch("local","a=>response::200::bye",$var(tmpvar))) {
		cache_remove("local","a=>response::200::bye");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, cseq, total) VALUES($var(f_date), $var(t_date), '200', 'BYE', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}

	#ALL TRANSACTIONS MESSAGES
	if(cache_fetch("local","a=>method::all",$var(tmpvar))) {
		cache_remove("local","a=>method::all");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'ALL', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}	
    
	#ALL MESSAGES ON INTERFACE
	if(cache_fetch("local","a=>method::total",$var(tmpvar))) {
		cache_remove("local","a=>method::total");
	        avp_db_query("INSERT INTO stats_method (from_date, to_date, method, total) VALUES($var(f_date), $var(t_date), 'TOTAL', $var(tmpvar)) ON DUPLICATE KEY UPDATE total=total+$var(tmpvar)");
	}    
}


route[STORE] {

        if($rm == "REGISTER") {
                $var(table) = "sip_capture_registration";       
        }
        else if($rm =~ "(INVITE|UPDATE|BYE|ACK|PRACK|REFER|CANCEL)$")
        {
                $var(table) = "sip_capture_call";
        } 
        else if($rm =~ "(NOTIFY)$" && is_present_hf("Event") && $hdr(Event)=~"refer;")
        {
                $var(table) = "sip_capture_call";
        }
        else if($rm =~ "(INFO)$")
        {
                $var(table) = "sip_capture_call";
        }
        else if($rm =~ "(OPTIONS)$" )
        {
            $var(table) = "sip_capture_rest";
        }
        else {   
            $var(table) = "sip_capture_rest";
        }
	
	#$var(utc) = "%Y%m%d";
	
	if($var(table) == "sip_capture_call") sip_capture("sip_capture_call_%Y%m%d");
	else if($var(table) == "sip_capture_registration") sip_capture("sip_capture_registration_%Y%m%d");
	else sip_capture("sip_capture_rest_%Y%m%d");
}


route[my_hep_route] {

        ### hep_get([data type,] chunk_id, vendor_id_pvar, chunk_data_pvar)
        ### data type is optional for most of the generic chunks
        ### Full list here: http://www.opensips.org/html/docs/modules/2.2.x/sipcapture#hep_set_id

	#Protocol ID
	hep_get("11", "$var(vid)", "$var(data)");

        $var(proto) = $(var(data){s.int});

	#Logs Or Stats
	if($var(proto) == 100 || $var(proto) == 99) {

		#hep_set("uint8", "2", , "1");
		hep_get("utf8-string", "0x11", "$var(vid)", "$var(correlation_id)");
		report_capture("logs_capture", "$var(correlation_id)", "1");
		exit;
	}

	hep_resume_sip();
	
}
