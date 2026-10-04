# Subscription download, cache, and refresh scheduling for proxy sections.

# Download and normalize a subscription with the same parser used by Forkop.
# The normalizer returns sing-box outbound JSON, so subscription formats do not
# need to be guessed from Content-Type or decoded with BusyBox-specific tools.
subscription_get_outbounds() {
    local section="$1" url="$2" cache_dir="$TMP_SING_BOX_FOLDER/subscriptions"
    local parser_file raw_file normalized_file next_file outbound_count skipped_message
    mkdir -p "$cache_dir"
    raw_file="$cache_dir/$section.download"
    parser_file="${PODKOP_LIB:-/usr/lib/podkop}/subscription_parser.uc"
    normalized_file="$cache_dir/$section.outbounds.json"
    next_file="$cache_dir/$section.outbounds.next"
    rm -f "$cache_dir/$section.changed"

    if curl -fLsS --connect-timeout 10 --max-time 30 "$url" -o "$raw_file"; then
        if ucode "$parser_file" normalize-content-validated "$raw_file" "$next_file" >/dev/null 2>&1 &&
            outbound_count=$(jq '[.outbounds[] | select(.type != "selector" and .type != "urltest" and .type != "direct" and .type != "block" and .type != "dns")] | length' "$next_file" 2>/dev/null) &&
            [ "$outbound_count" -gt 0 ]; then
            skipped_message=$(ucode "$parser_file" normalized-skipped-warning "$next_file" 2>/dev/null || true)
            [ -z "$skipped_message" ] || log "$skipped_message for subscription '$section'." "warn"
            if [ -s "$normalized_file" ] && ! cmp -s "$normalized_file" "$next_file"; then
                # A changed subscription invalidates the manually selected node.
                : > "$cache_dir/$section.changed"
            fi
            mv "$next_file" "$normalized_file"
        else
            log "Subscription '$section' returned an unsupported or empty URI list; keeping cached version if available." "warn"
            rm -f "$next_file"
        fi
    else
        log "Failed to download subscription '$section'; keeping cached version if available." "warn"
    fi

    [ -s "$normalized_file" ] || return 1
    printf '%s\n' "$normalized_file"
}

refresh_subscription_cron_jobs() {
    # Replace only Podkop subscription schedules, leaving user cron entries intact.
    (crontab -l 2>/dev/null | grep -v '# podkop-subscription-update') | crontab -
    config_foreach add_subscription_cron_job "section"
}

add_subscription_cron_job() {
    local section="$1" proxy_config_type subscription_url interval cron_job
    config_get proxy_config_type "$section" "proxy_config_type"
    config_get subscription_url "$section" "subscription_url"
    [ "$proxy_config_type" = "subscription" ] && [ -n "$subscription_url" ] || return 0
    config_get interval "$section" "subscription_update_interval" "12h"
    case "$interval" in
        1h) cron_job='13 * * * *' ;;
        3h) cron_job='13 */3 * * *' ;;
        12h) cron_job='13 */12 * * *' ;;
        1d) cron_job='13 9 * * *' ;;
        3d) cron_job='13 9 */3 * *' ;;
        *) log "Invalid subscription_update_interval for '$section': $interval; using 12h." "warn"; cron_job='13 */12 * * *' ;;
    esac
    (crontab -l 2>/dev/null; echo "$cron_job /etc/init.d/podkop reload # podkop-subscription-update-$section") | crontab -
}
