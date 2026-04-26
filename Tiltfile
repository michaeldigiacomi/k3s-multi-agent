# Tiltfile — Local development for k3s-multi-agent overlays

# Default overlay — override with: tilt up -- --overlay=openai
args = config.parse()
overlay = args.get('overlay', ['openai'])[0]

print("Tilt starting for overlay: " + overlay)

# Load overlay-specific config if present
overlay_tiltfile = "tilt-resources/" + overlay + "/Tiltfile"
if os.path.exists(overlay_tiltfile):
    load_dynamic(overlay_tiltfile)

# Watch persona files for hot-reload
watch_file('personas/')
watch_file('overlay-map.yaml')

# Sync personas before kustomize builds
local_resource(
    'sync-personas',
    cmd='./scripts/sync-personas.sh',
    deps=['personas/', 'overlay-map.yaml']
)

# Apply the kustomized overlay
k8s_yaml(
    local("kubectl kustomize overlays/" + overlay),
    allow_duplicates=True
)

# Define the k8s resource with port-forward
k8s_resource(
    'hermes',
    port_forwards=['8642:8642'],
    resource_deps=['sync-personas']
)
