#!/bin/bash

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/moode_project_install_$(date +%Y%m%d_%H%M%S).log"

# Get the actual username (user who invoked sudo)
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $(date): $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $(date): $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $(date): $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date): $1" >> "$LOG_FILE"
}

print_section() {
    echo -e "${PURPLE}=========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}=========================================${NC}"
}

# Function to run commands with sudo when needed
run_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Function to check and prompt for sudo
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        print_status "This script needs sudo privileges for certain operations."
        print_status "You may be prompted for your password."
        
        # Test sudo access
        if ! sudo -v; then
            print_error "Failed to get sudo privileges. Exiting."
            exit 1
        fi
        
        # Keep sudo alive in background
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    fi
}

# Function to validate directory structure
validate_structure() {
    print_section "Validating Project Directory Structure"
    
    local required_dirs=(
        "filesystem/etc/default"
        "filesystem/etc/icecast2"
        "filesystem/etc/modprobe.d"
        "filesystem/etc/systemd/system"
        "filesystem/etc/udev/rules.d"
        "filesystem/usr/local/bin"
        "filesystem/var/log"
    )
    
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        print_error "Missing required directories: ${missing_dirs[*]}"
        print_error "Please ensure your project has the correct filesystem structure."
        exit 1
    fi
    
    print_success "Directory structure validation complete"
}

# Function to add user to required groups
add_user_to_groups() {
    print_section "Adding User to Required Groups"
    
    local groups=("plugdev" "audio")
    local groups_added=false
    
    for group in "${groups[@]}"; do
        if groups $ACTUAL_USER | grep -q "\b$group\b"; then
            print_status "User $ACTUAL_USER is already in group $group"
        else
            print_status "Adding user $ACTUAL_USER to group $group..."
            if run_sudo usermod -a -G "$group" "$ACTUAL_USER"; then
                print_success "Added $ACTUAL_USER to group $group"
                groups_added=true
            else
                print_error "Failed to add $ACTUAL_USER to group $group"
            fi
        fi
    done
    
    if [[ "$groups_added" == true ]]; then
        print_warning "Group changes will take effect after logout/login or reboot"
    fi
}

# Function to install dependencies
install_dependencies() {
    print_section "Installing Dependencies"
    
    print_status "Updating package lists..."
    run_sudo apt-get update >> "$LOG_FILE" 2>&1
    
    # Core dependencies for nrsc5 and redsea
    local dependencies=(
        # Build tools
        git
        build-essential
        cmake
        autoconf
        libtool
        libao-dev
        libfftw3-dev
        librtlsdr-dev
        meson
        libsndfile1-dev
        libliquid-dev
        python3-flask
        icecast2
        rtl-sdr
        vorbis-tools
    )
    
    print_status "Installing packages: ${dependencies[*]}"
    if run_sudo apt-get install -y "${dependencies[@]}" >> "$LOG_FILE" 2>&1; then
        print_success "Dependencies installed successfully"
    else
        print_error "Failed to install dependencies. Check $LOG_FILE for details."
        exit 1
    fi
}

# Function to clone repositories
clone_repositories() {
    print_section "Cloning Git Repositories"
    
    # Create repos directory if it doesn't exist
    mkdir -p repos
    
    # Clone nrsc5
    if [[ ! -d "repos/nrsc5" ]]; then
        print_status "Cloning nrsc5 repository..."
        git clone https://github.com/theori-io/nrsc5.git repos/nrsc5 >> "$LOG_FILE" 2>&1
        print_success "nrsc5 cloned successfully"
    else
        print_status "nrsc5 repository already exists, updating..."
        cd repos/nrsc5
        git pull >> "$LOG_FILE" 2>&1
        cd ../..
        print_success "nrsc5 updated"
    fi
    
    # Clone redsea
    if [[ ! -d "repos/redsea" ]]; then
        print_status "Cloning redsea repository..."
        git clone https://github.com/windytan/redsea.git repos/redsea >> "$LOG_FILE" 2>&1
        print_success "redsea cloned successfully"
    else
        print_status "redsea repository already exists, updating..."
        cd repos/redsea
        git pull >> "$LOG_FILE" 2>&1
        cd ../..
        print_success "redsea updated"
    fi
}

# Function to compile and install nrsc5
compile_nrsc5() {
    print_section "Compiling and Installing nrsc5"
    
    cd repos/nrsc5
    
    # Create build directory
    if [[ -d "build" ]]; then
        print_status "Removing old build directory..."
        rm -rf build
    fi
    
    print_status "Creating build directory..."
    mkdir build
    cd build
    
    print_status "Running cmake..."
    cmake .. >> "$LOG_FILE" 2>&1
    
    print_status "Compiling nrsc5..."
    make -j$(nproc) >> "$LOG_FILE" 2>&1
    
    print_status "Installing nrsc5 (requires sudo)..."
    if run_sudo make install >> "$LOG_FILE" 2>&1; then
        print_success "nrsc5 installed successfully"
    else
        print_error "Failed to install nrsc5"
        exit 1
    fi
    
    # Run ldconfig to update library cache
    print_status "Updating library cache..."
    run_sudo ldconfig >> "$LOG_FILE" 2>&1
    
    cd ../..
    print_success "nrsc5 compilation and installation complete"
}

# Function to compile and install redsea
compile_redsea() {
    print_section "Compiling and Installing redsea"
    
    cd repos/redsea
    
    # Remove old build if exists
    if [[ -d "build" ]]; then
        print_status "Removing old build directory..."
        rm -rf build
    fi
    
    print_status "Setting up meson build..."
    meson setup build >> "$LOG_FILE" 2>&1
    
    cd build
    
    print_status "Compiling redsea..."
    meson compile >> "$LOG_FILE" 2>&1
    
    print_status "Installing redsea (requires sudo)..."
    if run_sudo meson install >> "$LOG_FILE" 2>&1; then
        print_success "redsea installed successfully"
    else
        print_error "Failed to install redsea"
        exit 1
    fi
    
    cd ../..
    print_success "redsea compilation and installation complete"
}

# Function to copy files with proper permissions
copy_files() {
    print_section "Copying Project Files"
    
    # Copy to /etc/default
    if [[ -d "filesystem/etc/default" ]] && [[ -n "$(ls -A filesystem/etc/default 2>/dev/null)" ]]; then
        print_status "Copying files to /etc/default..."
        for file in filesystem/etc/default/*; do
            if [[ -f "$file" ]]; then
                target="/etc/default/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    # Copy to /etc/icecast2
    if [[ -d "filesystem/etc/icecast2" ]] && [[ -n "$(ls -A filesystem/etc/icecast2 2>/dev/null)" ]]; then
        print_status "Copying files to /etc/icecast2..."
        for file in filesystem/etc/icecast2/*; do
            if [[ -f "$file" ]]; then
                target="/etc/icecast2/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    # Copy to /etc/modprobe.d
    if [[ -d "filesystem/etc/modprobe.d" ]] && [[ -n "$(ls -A filesystem/etc/modprobe.d 2>/dev/null)" ]]; then
        print_status "Copying files to /etc/modprobe.d..."
        for file in filesystem/etc/modprobe.d/*; do
            if [[ -f "$file" ]]; then
                target="/etc/modprobe.d/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    # Copy to /etc/systemd/system
    if [[ -d "filesystem/etc/systemd/system" ]] && [[ -n "$(ls -A filesystem/etc/systemd/system 2>/dev/null)" ]]; then
        print_status "Copying service files to /etc/systemd/system..."
        for file in filesystem/etc/systemd/system/*.service; do
            if [[ -f "$file" ]]; then
                target="/etc/systemd/system/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    # Copy to /etc/udev/rules.d
    if [[ -d "filesystem/etc/udev/rules.d" ]] && [[ -n "$(ls -A filesystem/etc/udev/rules.d 2>/dev/null)" ]]; then
        print_status "Copying udev rules to /etc/udev/rules.d..."
        for file in filesystem/etc/udev/rules.d/*.rules; do
            if [[ -f "$file" ]]; then
                target="/etc/udev/rules.d/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
        
        # Reload udev rules
        print_status "Reloading udev rules..."
        run_sudo udevadm control --reload-rules
        run_sudo udevadm trigger
    fi
    
    # Copy scripts to /usr/local/bin
    if [[ -d "filesystem/usr/local/bin" ]] && [[ -n "$(ls -A filesystem/usr/local/bin 2>/dev/null)" ]]; then
        print_status "Copying scripts to /usr/local/bin..."
        for file in filesystem/usr/local/bin/*; do
            if [[ -f "$file" ]]; then
                target="/usr/local/bin/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                
                # Make scripts executable
                if [[ "$file" == *.sh ]] || [[ "$file" == *.py ]] || [[ ! "$file" =~ \. ]]; then
                    run_sudo chmod 755 "$target"
                    print_status "Set executable permissions for $(basename "$file")"
                else
                    run_sudo chmod 644 "$target"
                fi
                
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    # Copy to /var/log
    if [[ -d "filesystem/var/log" ]] && [[ -n "$(ls -A filesystem/var/log 2>/dev/null)" ]]; then
        print_status "Copying files to /var/log..."
        for file in filesystem/var/log/*; do
            if [[ -f "$file" ]]; then
                target="/var/log/$(basename "$file")"
                print_status "Copying $file to $target"
                run_sudo cp "$file" "$target"
                run_sudo chmod 644 "$target"
                run_sudo chown root:root "$target"
                print_success "Copied $(basename "$file")"
            fi
        done
    fi
    
    print_success "All files copied successfully"
}

# Function to enable and start services
enable_services() {
    print_section "Enabling Systemd Services"
    
    if [[ -d "filesystem/etc/systemd/system" ]]; then
        # Reload systemd first
        run_sudo systemctl daemon-reload
        
        for service_file in filesystem/etc/systemd/system/*.service; do
            if [[ -f "$service_file" ]]; then
                service_name=$(basename "$service_file")
                
                print_status "Processing service: $service_name"
                
                # Enable service
                if run_sudo systemctl enable "$service_name" >> "$LOG_FILE" 2>&1; then
                    print_success "Enabled $service_name"
                else
                    print_warning "Failed to enable $service_name"
                fi
                
                # Start service
                if run_sudo systemctl start "$service_name" >> "$LOG_FILE" 2>&1; then
                    print_success "Started $service_name"
                else
                    print_warning "Failed to start $service_name"
                fi
            fi
        done
    fi
}

# Function to verify installation
verify_installation() {
    print_section "Verifying Installation"
    
    # Check if nrsc5 is installed
    if command -v nrsc5 >/dev/null 2>&1; then
        nrsc5_version=$(nrsc5 --version 2>&1 | head -n1 || echo "version unknown")
        print_success "nrsc5 installed: $nrsc5_version"
    else
        print_warning "nrsc5 not found in PATH"
    fi
    
    # Check if redsea is installed
    if command -v redsea >/dev/null 2>&1; then
        redsea_version=$(redsea --version 2>&1 | head -n1 || echo "version unknown")
        print_success "redsea installed: $redsea_version"
    else
        print_warning "redsea not found in PATH"
    fi
    
    # Check for RTL-SDR devices
    if command -v rtl_test >/dev/null 2>&1; then
        print_status "Checking for RTL-SDR devices..."
        if rtl_test -t 1 >/dev/null 2>&1; then
            print_success "RTL-SDR device detected"
        else
            print_warning "No RTL-SDR device detected. Check connections and permissions."
        fi
    fi
    
    # Check if services are running
    if [[ -d "filesystem/etc/systemd/system" ]]; then
        for service_file in filesystem/etc/systemd/system/*.service; do
            if [[ -f "$service_file" ]]; then
                service_name=$(basename "$service_file")
                if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                    print_success "Service $service_name is running"
                else
                    print_status "Service $service_name status: $(systemctl is-active "$service_name" 2>/dev/null || echo 'not active')"
                fi
            fi
        done
    fi
    
    # Verify key configuration files
    print_status "Checking key configuration files..."
    local config_files=(
        "/etc/icecast2/icecast.xml"
        "/etc/udev/rules.d/20-rtlsdr.rules"
    )
    
    for config in "${config_files[@]}"; do
        if [[ -f "$config" ]]; then
            print_success "Found $config"
        else
            print_warning "Missing $config"
        fi
    done
    
    print_success "Verification complete"
}

# Function to cleanup
cleanup() {
    print_section "Cleaning Up"
    print_status "Log file saved at: $LOG_FILE"
    print_success "Cleanup complete"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -s, --skip-deps     Skip dependency installation"
    echo "  -c, --clean         Clean build directories before compilation"
    echo "  -v, --verbose       Verbose output (tee to log file)"
    echo "  -n, --no-build      Skip compilation (use existing builds)"
    echo "  -u, --update        Update repositories only"
}

# Main installation function
main() {
    local skip_deps=false
    local clean_build=false
    local no_build=false
    local update_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
                exit 0
                ;;
            -s|--skip-deps)
                skip_deps=true
                shift
                ;;
            -c|--clean)
                clean_build=true
                shift
                ;;
            -v|--verbose)
                exec > >(tee -a "$LOG_FILE")
                exec 2>&1
                shift
                ;;
            -n|--no-build)
                no_build=true
                shift
                ;;
            -u|--update)
                update_only=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Print banner
    echo -e "${PURPLE}"
    echo "============================================"
    echo "  moOde Audio HD Radio Installation Script"
    echo "  NRSC5 + Redsea Installer"
    echo "============================================"
    echo -e "${NC}"
    echo "Log file: $LOG_FILE"
    echo "User: $ACTUAL_USER"
    echo ""
    
    # Check sudo access
    check_sudo
    
    # Validate directory structure
    validate_structure
    
    # Add user to required groups
    add_user_to_groups
    
    # Update only mode
    if [[ "$update_only" == true ]]; then
        print_section "Update Mode - Only Updating Repositories"
        clone_repositories
        print_success "Update complete"
        exit 0
    fi
    
    # Install dependencies
    if [[ "$skip_deps" == false ]]; then
        install_dependencies
    else
        print_warning "Skipping dependency installation as requested"
    fi
    
    # Clone repositories
    clone_repositories
    
    # Clean if requested
    if [[ "$clean_build" == true ]]; then
        print_status "Cleaning build directories..."
        rm -rf repos/nrsc5/build repos/redsea/build
        print_success "Build directories cleaned"
    fi
    
    # Compile repositories
    if [[ "$no_build" == false ]]; then
        compile_nrsc5
        compile_redsea
    else
        print_warning "Skipping compilation as requested"
    fi
    
    # Copy files
    copy_files
    
    # Enable services
    enable_services
    
    # Verify installation
    verify_installation
    
    print_section "Installation Complete"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "  1. Log out and log back in for group changes to take effect"
    echo "  2. Connect your RTL-SDR device"
    echo "  3. Check service status: systemctl status <your-service-name>"
    echo "  4. Test reception: nrsc5 -o - 93.3 | redsea"
    echo "  5. Reboot if necessary: sudo reboot"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Cleanup
    cleanup
}

# Trap exit to ensure cleanup
trap cleanup EXIT

# Run main function
main "$@"