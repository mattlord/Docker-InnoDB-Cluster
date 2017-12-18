
if [ "$NODE_TYPE" = 'router' ]; then
	# Router exposes no monitoring interface, so let's just see if it's still responding to signals
	# If so, then it will be marked as healthy 
	kill -0 1
else
	# Let's see if the node is in the OFFLINE or ERROR state
	# If not, then it will be marked as healthy 

	mysql -h localhost -nsLNE -e "select member_state from performance_schema.replication_group_members where member_id=@@server_uuid;" 2>/dev/null | grep -v "*" | egrep -v "ERROR|OFFLINE"
fi
