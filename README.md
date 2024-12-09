# Generating Installers

These mix tasks generate binary installers for your Elixir-Desktop project in corresponding native formats. Currently supported output formats are:

* Windows: `.exe` installer (NSIS based)
* MacOS: `.dmg` download package
* Linux: `.run` makeself installer.

## Usage

1. Add a new release to your project configuration that includes the `&Desktop.Deployment.generate_installer/1` steps
2. Add the `package: package()` configuration with your app packaging information. If you don't provide these, default values will be used.
3. Run `mix desktop.installer` to generate the installer for your current OS

```elixir
  def project do
    [
      package: package(),
      releases: [
        default: [
          applications: [runtime_tools: :permanent, ssl: :permanent],
          steps: [:assemble, &Desktop.Deployment.generate_installer/1]
        ],
      ],
    ]
  end

  def package() do
    [
      name: "MyApp",
      name_long: "The most wonderfull App Ever",
      description: "MyApp is an Elixir App for Desktop",
      description_long: "MyApp for Desktop is powered by Phoenix LiveView",
      icon: "priv/icon.png",
      # https://developer.gnome.org/menu-spec/#additional-category-registry
      category_gnome: "GNOME;GTK;Office;",
      category_macos: "public.app-category.productivity",
      identifier: "io.myapp.app",
    ]
  end  
```

## Installation

The the package can be installed
by adding `desktop_deployment` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:desktop_deployment, "~> 0.1", runtimes: false}
  ]
end
```

## Deployment Strategies

### Windows -> NSIS

All builds (specifically NIFs) are built using msys2, because it's mostly linux compatible but runs natively on windows without any helper libraries. 

0) Installing prerequsites
  - msys2.org
  - `pacman -S mingw-w64-x86_64-imagemagick mingw-w64-x86_64-nsis mingw-w64-x86_64-nsis mingw-w64-x86_64-osslsigncode mingw-w64-x86_64-openssl`

1) `mix deployment` will generate the release binaries

To support windows code signing the user has to create two certificate files `app_key.pem` and `app_key.pem` (e.g. get from sectigo) and put them into the `rel/win32/` subdirectory. 

#### Known Issues / Comments

* The `.vbs` file is used as indirection for the `.bat` file as it avoid creating a black terminal screen that otherwise flashes shortly when launchin a `.bat` file directly

* The `.nsis` file currently registers a `app://` protocol handler, this is example use and can be removed for other apps.

* After having done static builds for iOS now we're thinking a pure `.exe` build for Windows might actually be a much cleaner solution. But TBD

### MacOS -> DMG

The builds are all done on an x86_64 apple machine and we're enabling rosetta explicitly in the `.plist` file for M1 machines.

To run either you will need a macos development account. There are two environment variables this depends on `DEVELOPER_ID` which is set by `build_macos.sh` automatically using the default. `AC_PASSWORD` which is the API key for your account

1) `build_macos.sh`
2) `notarize_macos.sh`

#### Known Issues / Comments

* Background images for the deployment window of the `.dmg` (when clicking that on macos) are hardcoded in the rel/macosx/ subdirectory. I've not yet discovered how to properly (dynamically) create them. Also haven't found out how to set the DMGs icon to be non-standard as some apps do.

* The DMG should be notarized in two phases but right now it's not :-(

    1) Notarize the app directory (by zipping and uploading it)
    1) Staple the ticket to the app directory and all executables
    1) Package the app directory into the dmg, notarize the dmg
    1) Staple the ticket to the dmg

* Best to use a really recent wxWidgets on macos, such as wxWidgets (3.1.6) as e.g. taskbar icon size bug fixes are only present there.

### Linux -> makeself

#### Known Issues / Comments

* wxWidgets notifications+taskbar support is really varying accross distributions. Currently we have a pure Elixir dbus implementation.

* Getting distribution independent linux binaries is really though. Main issues have been library dependencies of different versions. Future thoughts for this:
    * Switch to AppImage
    * Switch to deb packages
    * other?

# Build dependencies

## Building on Ubuntu Linux

**Install Dependencies and Tools:**
```
# Tools
sudo apt install curl git inotify-tools libtool automake make lksctp-tools build-essential
# Build dependencies
sudo apt install libssl-dev libjpeg-dev libpng-dev libtiff-dev zlib1g-dev libncurses5-dev libssh-dev unixodbc-dev libgmp3-dev libwebkit2gtk-4.0-dev libsctp-dev libgtk-3-dev libnotify-dev libsecret-1-dev catch mesa-common-dev libglu1-mesa-dev freeglut3-dev
```

**Install wxWidgets 3.1.5:**
```
mkdir ~/projects && cd ~/projects
git clone https://github.com/dominicletz/wxWidgets.git
cd wxWidgets
git submodule update --init
./configure --enable-compat30
make -j4
```

**Install Erlang OTP24:**
```
curl -O https://raw.githubusercontent.com/kerl/kerl/master/kerl
chmod a+x kerl
sudo mv kerl /usr/bin/
export LD_LIBRARY_PATH=$HOME/projects/wxWidgets/lib
export KERL_CONFIGURE_OPTIONS=--with-wxdir=$HOME/projects/wxWidgets
kerl build git https://github.com/diodechain/otp.git diode/beta 24.beta
kerl install 24.beta ~/24.beta
. ~/24.beta/activate
```

**Install Elixir:**
```
mkdir $HOME/elixir && cd $HOME/elixir
wget https://github.com/elixir-lang/elixir/releases/download/v1.11.4/Precompiled.zip
unzip Precompiled.zip
echo "export PATH=\"$HOME/elixir/bin:\$PATH\"" >> ~/.bashrc
export PATH="$HOME/elixir/bin:$PATH"
```

**Install NodeJS:**

```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash
nvm install v12.16.1
```
*Note: If you get "nvm: command not found" after running "nvm install v12.16.1" in the terminal, try closing the current teminal, opening a new one, and then running "nvm install v12.16.1" again. (see https://github.com/nvm-sh/nvm/blob/master/README.md#troubleshooting-on-linux for more information).*

## Building on macOS

**Start with the dependencies:**

```
brew install binutils automake elixir kerl libtool gmp
export PATH=/usr/local/opt/binutils/bin:$PATH
```

WxWidgets with recent macOS fixes

```
mkdir -p ~/projects/
cd ~/projects/
git clone https://github.com/dominicletz/wxWidgets.git
cd wxWidgets
git submodule update --init
./configure --enable-compat30
make -j4
```

**Build with kerl**

```
kerl build git https://github.com/diodechain/otp.git diode/beta 24.beta
kerl install 24.beta ~/24.beta
. ~/24.beta/activate
```

**Install nodejs / npm 12.16.1**

```
brew install npm
nvm install v12.16.1
cd assets && npm install && cd ..
```

**Compile and run:**

```
mix local.hex --force
mix local.rebar --force
mix deps.get

. ~/24.beta/activate
./run
```

## Building on Windows
**Install Dependencies:**

Get Erlang 24:diode/beta http://github.com/diodechain/

Get Elixir 1.11.4 https://elixir-lang.org/install.html

Get msys2 https://www.msys2.org/ - And a whole bunch of deps:
pacman -Syu
pacman -S --noconfirm pacman-mirrors pkg-config
pacman -S --noconfirm --needed base-devel autoconf automake make libtool mingw-w64-x86_64-toolchain mingw-w64-x86_64-openssl mingw-w64-x86_64-libtool git

Get nsis https://nsis.sourceforge.io/Main_Page

Get npm & node 12.x from https://nodejs.org/dist/latest-v12.x/

If not merged yet apply this patch on esqlite:
https://github.com/blt/port_compiler/pull/69/files

    > vim `find -iname pc_port_specs.erl`
    > find -iname pc_port_specs.beam -delete

Sometimes libsecp256k_nif.dll is not created in that case copy the libsecp256k_nif.so to libsecp256k_nif.dll > make -C deps/

**Compile & Run:**

Keep pressing ENTER during the compilation or it gets stuck...
