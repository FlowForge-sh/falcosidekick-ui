#!/bin/bash

echo "🚀 INTENSIVE LOAD TEST: Redis Backend with RediSearch"
echo "======================================================"

# Configuration
TARGET="localhost:2802"
CONCURRENT_CLIENTS=20
EVENTS_PER_CLIENT=500
TOTAL_EVENTS=$((CONCURRENT_CLIENTS * EVENTS_PER_CLIENT))

echo "Configuration:"
echo "- Target: $TARGET"
echo "- Concurrent clients: $CONCURRENT_CLIENTS"
echo "- Events per client: $EVENTS_PER_CLIENT"
echo "- Total events: $TOTAL_EVENTS"
echo ""

# Start the Redis backend
echo "🔄 Starting falcosidekick-ui with Redis backend..."
FALCOSIDEKICK_UI_DATABASE_BACKEND=redis \
FALCOSIDEKICK_UI_REDIS_URL=localhost:6379 \
/tmp/falcosidekick-ui -x true -l debug -d &
BACKEND_PID=$!

# Wait for startup
sleep 5

# Function to send events
send_events() {
    local client_id=$1
    local events_count=$2
    local start_time=$(date +%s)
    
    for i in $(seq 1 $events_count); do
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local priority_array=("Emergency" "Alert" "Critical" "Error" "Warning" "Notice" "Info" "Debug")
        local priority=${priority_array[$((RANDOM % ${#priority_array[@]}))]}
        
        curl -s -X POST http://$TARGET/api/v1/ \
            -H "Content-Type: application/json" \
            -d "{
                \"event\": {
                    \"uuid\": \"$uuid\",
                    \"output\": \"Load test event $i from client $client_id - Redis backend stress test\",
                    \"priority\": \"$priority\",
                    \"rule\": \"Redis Load Test Rule $((i % 10))\",
                    \"time\": \"$timestamp\",
                    \"source\": \"load-test-redis-client-$client_id\",
                    \"output_fields\": {\"client\": \"$client_id\", \"event_num\": \"$i\", \"backend\": \"redis\"},
                    \"hostname\": \"load-test-host-$((client_id % 5))\",
                    \"tags\": [\"load-test\", \"redis\", \"client-$client_id\"]
                },
                \"outputs\": [\"redis-test\"]
            }" > /dev/null
        
        # Brief pause to avoid overwhelming
        if [ $((i % 100)) -eq 0 ]; then
            echo "Client $client_id: Sent $i/$events_count events"
            sleep 0.1
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "✅ Client $client_id completed: $events_count events in ${duration}s ($(($events_count / $duration)) events/sec)"
}

# Start concurrent load test
echo "🔥 Starting intensive load test..."
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
echo "📊 LOAD TEST RESULTS:"
echo "- Total events sent: $TOTAL_EVENTS"
echo "- Total time: ${duration}s"
echo "- Average throughput: ${events_per_sec} events/sec"
echo ""

# Test search functionality under load
echo "🔍 Testing search functionality after load..."
search_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=100" | jq '.statistics' || echo "Search test failed"
search_end=$(date +%s)
echo "Search response time: $((search_end - search_start))s"

# Test aggregation under load
echo "📈 Testing aggregation functionality..."
agg_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/count/priority" | jq '.statistics' || echo "Aggregation test failed"
agg_end=$(date +%s)
echo "Aggregation response time: $((agg_end - agg_start))s"

# Simulate Redis index corruption scenario
echo "🔧 Testing Redis index recovery (simulating issue #146)..."
sudo docker exec redis-stack redis-cli FLUSHALL
sleep 2

# Try to search immediately after flush (should trigger auto-recovery)
echo "Attempting search after Redis flush (testing auto-recovery)..."
recovery_start=$(date +%s)
curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=10" | jq '.statistics' || echo "Auto-recovery test completed"
recovery_end=$(date +%s)
echo "Auto-recovery response time: $((recovery_end - recovery_start))s"

echo ""
echo "🎯 Redis Backend Load Test Complete!"
echo "Backend PID: $BACKEND_PID (kill with: kill $BACKEND_PID)"
