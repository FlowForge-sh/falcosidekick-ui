#!/bin/bash

echo "🐘 INTENSIVE LOAD TEST: PostgreSQL Backend"
echo "=========================================="

# Configuration
TARGET="localhost:2802"
CONCURRENT_CLIENTS=25
EVENTS_PER_CLIENT=800
TOTAL_EVENTS=$((CONCURRENT_CLIENTS * EVENTS_PER_CLIENT))

echo "Configuration:"
echo "- Target: $TARGET"
echo "- Concurrent clients: $CONCURRENT_CLIENTS"
echo "- Events per client: $EVENTS_PER_CLIENT"
echo "- Total events: $TOTAL_EVENTS"
echo ""

# Start the PostgreSQL backend
echo "🔄 Starting falcosidekick-ui with PostgreSQL backend..."
FALCOSIDEKICK_UI_DATABASE_BACKEND=postgres \
FALCOSIDEKICK_UI_POSTGRES_HOST=localhost \
FALCOSIDEKICK_UI_POSTGRES_PORT=5432 \
FALCOSIDEKICK_UI_POSTGRES_USER=falco \
FALCOSIDEKICK_UI_POSTGRES_PASSWORD=falco \
FALCOSIDEKICK_UI_POSTGRES_DB=falco \
/tmp/falcosidekick-ui -x true -l debug -d &
BACKEND_PID=$!

# Wait for startup
sleep 5

# Function to send events with more complex data
send_events() {
    local client_id=$1
    local events_count=$2
    local start_time=$(date +%s)
    
    for i in $(seq 1 $events_count); do
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local priority_array=("Emergency" "Alert" "Critical" "Error" "Warning" "Notice" "Info" "Debug")
        local source_array=("k8s" "docker" "systemd" "nginx" "mysql" "postgres" "redis" "falco")
        local priority=${priority_array[$((RANDOM % ${#priority_array[@]}))]}
        local source=${source_array[$((RANDOM % ${#source_array[@]}))]}
        
        # Create more complex output fields
        local node_id=$((RANDOM % 10))
        local container_id="container-$((RANDOM % 100))"
        
        curl -s -X POST http://$TARGET/api/v1/ \
            -H "Content-Type: application/json" \
            -d "{
                \"event\": {
                    \"uuid\": \"$uuid\",
                    \"output\": \"PostgreSQL load test event $i from client $client_id - testing database resilience with complex data structures and long text fields that simulate real-world Falco events\",
                    \"priority\": \"$priority\",
                    \"rule\": \"PostgreSQL Stress Test Rule for $source\",
                    \"time\": \"$timestamp\",
                    \"source\": \"$source\",
                    \"output_fields\": {
                        \"client_id\": \"$client_id\",
                        \"event_number\": \"$i\",
                        \"backend\": \"postgresql\",
                        \"node_id\": \"node-$node_id\",
                        \"container_id\": \"$container_id\",
                        \"process_name\": \"load-test-process\",
                        \"file_path\": \"/var/log/test-$i.log\",
                        \"user_name\": \"test-user-$((i % 5))\",
                        \"command_line\": \"./load-test --client=$client_id --event=$i\",
                        \"network_connection\": \"tcp://192.168.1.$((i % 255)):$((8000 + (i % 1000)))\",
                        \"metadata\": {\"test\": true, \"load_test\": \"postgresql\"}
                    },
                    \"hostname\": \"postgres-test-host-$((client_id % 8))\",
                    \"tags\": [\"load-test\", \"postgresql\", \"stress-test\", \"client-$client_id\", \"batch-$((i / 100))\"]
                },
                \"outputs\": [\"postgres-test\"]
            }" > /dev/null
        
        # Progress reporting and brief pauses
        if [ $((i % 200)) -eq 0 ]; then
            echo "Client $client_id: Sent $i/$events_count events to PostgreSQL"
            sleep 0.05
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "✅ Client $client_id completed: $events_count events in ${duration}s ($(($events_count / $duration)) events/sec)"
}

# Start concurrent load test
echo "🔥 Starting intensive PostgreSQL load test..."
start_time=$(date +%s)

# Launch concurrent clients
for client in $(seq 1 $CONCURRENT_CLIENTS); do
    send_events $client $EVENTS_PER_CLIENT &
done

# Wait for all clients to finish
wait

end_time=$(date +%s)
duration=$((end_time - start_time))
events_per_sec=$((TOTAL_EVENTS / duration))

echo ""
echo "📊 POSTGRESQL LOAD TEST RESULTS:"
echo "- Total events sent: $TOTAL_EVENTS"
echo "- Total time: ${duration}s"
echo "- Average throughput: ${events_per_sec} events/sec"
echo ""

# Test search functionality under load
echo "🔍 Testing search functionality after heavy load..."
search_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=100&priority=Critical" | jq '.statistics' || echo "Search test failed"
search_end=$(date +%s)
echo "Search response time: $((search_end - search_start))s"

# Test complex aggregations
echo "📈 Testing aggregation functionality with large dataset..."
agg_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/count/priority" | jq '.statistics' || echo "Priority aggregation failed"
curl -s -u admin:admin "http://$TARGET/api/v1/events/count/source" | jq '.statistics' || echo "Source aggregation failed"
curl -s -u admin:admin "http://$TARGET/api/v1/events/count/hostname" | jq '.statistics' || echo "Hostname aggregation failed"
agg_end=$(date +%s)
echo "Aggregation response time: $((agg_end - agg_start))s"

# Test filtering with large dataset
echo "🎯 Testing complex filtering..."
filter_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?priority=Critical,Alert&source=k8s&limit=50" | jq '.statistics' || echo "Filter test failed"
filter_end=$(date +%s)
echo "Filter response time: $((filter_end - filter_start))s"

# Test database resilience - simulate connection drops
echo "💪 Testing PostgreSQL resilience (connection drop simulation)..."
echo "Stopping PostgreSQL container..."
sudo docker stop postgres
sleep 3

# Try to search during outage
echo "Attempting operations during PostgreSQL outage..."
outage_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=10" 2>/dev/null || echo "Expected: Connection refused during outage"
outage_end=$(date +%s)
echo "Outage detection time: $((outage_end - outage_start))s"

# Restart PostgreSQL
echo "Restarting PostgreSQL container..."
sudo docker start postgres
sleep 10

# Test recovery
echo "Testing recovery after PostgreSQL restart..."
recovery_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=5" | jq '.statistics' || echo "Recovery test in progress..."
recovery_end=$(date +%s)
echo "Recovery response time: $((recovery_end - recovery_start))s"

# Check data persistence
echo "🔒 Verifying data persistence..."
persistence_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/count" | jq '.statistics.all' || echo "Persistence check failed"
persistence_end=$(date +%s)
echo "Persistence check time: $((persistence_end - persistence_start))s"

echo ""
echo "🎯 PostgreSQL Backend Load Test Complete!"
echo "Backend PID: $BACKEND_PID (kill with: kill $BACKEND_PID)"
