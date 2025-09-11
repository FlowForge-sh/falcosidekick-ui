#!/bin/bash

echo "🎯 REDIS THRESHOLD TEST: 100 events/sec sustained load"
echo "====================================================="

# Configuration for optimal threshold testing
TARGET="localhost:2802"
EVENTS_PER_SECOND=100
TEST_DURATION=60
TOTAL_EVENTS=$((EVENTS_PER_SECOND * TEST_DURATION))
BATCH_SIZE=10
BATCHES_PER_SECOND=$((EVENTS_PER_SECOND / BATCH_SIZE))
SLEEP_BETWEEN_BATCHES=$(echo "scale=3; 1.0 / $BATCHES_PER_SECOND" | bc)

echo "Configuration:"
echo "- Target rate: $EVENTS_PER_SECOND events/sec"
echo "- Test duration: ${TEST_DURATION}s" 
echo "- Total events: $TOTAL_EVENTS"
echo "- Batch size: $BATCH_SIZE events"
echo "- Batches per second: $BATCHES_PER_SECOND"
echo "- Sleep between batches: ${SLEEP_BETWEEN_BATCHES}s"
echo ""

# Start Redis backend
echo "🔄 Starting Redis backend..."
FALCOSIDEKICK_UI_DATABASE_BACKEND=redis \
FALCOSIDEKICK_UI_REDIS_URL=localhost:6379 \
/tmp/falcosidekick-ui -x true -l info -d > /tmp/redis-threshold.log 2>&1 &
BACKEND_PID=$!

sleep 5

# Verify backend is running
if ! curl -s http://$TARGET/api/v1/healthz | grep -q "ok"; then
    echo "❌ Backend failed to start"
    kill $BACKEND_PID 2>/dev/null
    exit 1
fi

echo "✅ Redis backend started (PID: $BACKEND_PID)"

# Function to send a controlled batch
send_controlled_batch() {
    local batch_id=$1
    local success_count=0
    
    for i in $(seq 1 $BATCH_SIZE); do
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local priority_array=("Critical" "Warning" "Info" "Error")
        local priority=${priority_array[$((RANDOM % 4))]}
        
        if curl -s -X POST http://$TARGET/api/v1/ \
            -H "Content-Type: application/json" \
            -d "{
                \"event\": {
                    \"uuid\": \"$uuid\",
                    \"output\": \"Redis threshold test batch $batch_id event $i - controlled load at 100 events/sec\",
                    \"priority\": \"$priority\",
                    \"rule\": \"Redis Threshold Test Rule\",
                    \"time\": \"$timestamp\",
                    \"source\": \"redis-threshold-test\",
                    \"output_fields\": {\"batch\": \"$batch_id\", \"event\": \"$i\", \"test\": \"threshold\"},
                    \"hostname\": \"redis-threshold-host\",
                    \"tags\": [\"threshold\", \"redis\", \"controlled\"]
                },
                \"outputs\": [\"threshold-test\"]
            }" > /dev/null 2>&1; then
            ((success_count++))
        fi
    done
    
    echo "$success_count"
}

# Run controlled load test
echo "🚀 Starting controlled threshold test..."
total_start=$(date +%s)
total_sent=0
total_success=0

for second in $(seq 1 $TEST_DURATION); do
    second_start=$(date +%s.%3N)
    second_success=0
    
    # Send batches for this second
    for batch in $(seq 1 $BATCHES_PER_SECOND); do
        batch_start=$(date +%s.%3N)
        
        success=$(send_controlled_batch "$second-$batch")
        second_success=$((second_success + success))
        total_success=$((total_success + success))
        total_sent=$((total_sent + BATCH_SIZE))
        
        # Sleep to maintain rate
        batch_end=$(date +%s.%3N)
        batch_duration=$(echo "$batch_end - $batch_start" | bc)
        sleep_time=$(echo "$SLEEP_BETWEEN_BATCHES - $batch_duration" | bc)
        
        if (( $(echo "$sleep_time > 0" | bc -l) )); then
            sleep $sleep_time
        fi
    done
    
    # Progress report every 10 seconds
    if [ $((second % 10)) -eq 0 ]; then
        success_rate=$(echo "scale=1; $second_success * 100 / $EVENTS_PER_SECOND" | bc)
        echo "Second $second: ${second_success}/${EVENTS_PER_SECOND} events (${success_rate}% success)"
    fi
done

total_end=$(date +%s)
actual_duration=$((total_end - total_start))

echo ""
echo "📊 REDIS THRESHOLD TEST RESULTS:"
echo "- Target events: $TOTAL_EVENTS"
echo "- Events sent: $total_sent"
echo "- Events successful: $total_success"
echo "- Success rate: $(echo "scale=1; $total_success * 100 / $total_sent" | bc)%"
echo "- Actual duration: ${actual_duration}s"
echo "- Actual rate: $(echo "scale=1; $total_success / $actual_duration" | bc) events/sec"

# Test functionality after load
echo ""
echo "🔍 Testing functionality after sustained load..."
search_start=$(date +%s.%3N)
search_result=$(curl -s -u admin:admin "http://$TARGET/api/v1/events/search?limit=10")
search_end=$(date +%s.%3N)
search_time=$(echo "$search_end - $search_start" | bc)

if echo "$search_result" | jq -e '.statistics' > /dev/null 2>&1; then
    event_count=$(echo "$search_result" | jq -r '.statistics.all')
    echo "✅ Search functional: $event_count total events (${search_time}s response)"
else
    echo "❌ Search failed after load test"
fi

# Test aggregation
agg_start=$(date +%s.%3N)
agg_result=$(curl -s -u admin:admin "http://$TARGET/api/v1/events/count/priority")
agg_end=$(date +%s.%3N)
agg_time=$(echo "$agg_end - $agg_start" | bc)

if echo "$agg_result" | jq -e '.statistics' > /dev/null 2>&1; then
    echo "✅ Aggregation functional (${agg_time}s response)"
    echo "$agg_result" | jq '.results'
else
    echo "❌ Aggregation failed after load test"
fi

echo ""
echo "🎯 Redis Threshold Test Complete!"
echo "Backend PID: $BACKEND_PID (kill with: kill $BACKEND_PID)"
