@echo off
setlocal EnableDelayedExpansion EnableExtensions

REM Option flags
set /a valid_cc=0
set /a use_local=0
set /a verbose_log=0
set /a shift_counter=0

REM Option variables
set log_file="%TEMP%\v_make.log"
set compiler=""
set target=""

REM tcc variables
set "tcc_url=https://github.com/vlang/tccbin_win.git"
set "tcc_dir=%~dp0thirdparty\tcc"
set "vc_url=https://github.com/vlang/vc.git"
set "vc_dir=%~dp0vc"

REM Let a particular environment specify their own tcc repo
if /I not ["%TCC_GIT%"] == [""] set "tcc_url=%TCC_GIT%"

pushd %~dp0

:verifyopt
REM Read stdin EOF
if ["%~1"] == [""] goto :init

REM Target options
if !shift_counter! LSS 1 (
    if "%~1" == "build" set target="build"& shift& set /a shift_counter+=1& goto :verifyopt
    if "%~1" == "clean" set target="clean"& shift& set /a shift_counter+=1& goto :verifyopt
    if "%~1" == "clean-all" set target="clean-all"& shift& set /a shift_counter+=1& goto :verifyopt
    if "%~1" == "help" (
        if "%~2" == "build" call :help_build& exit /b %ERRORLEVEL%
        if "%~2" == "clean" call :help_clean& exit /b %ERRORLEVEL%
        if "%~2" == "clean-all" call :help_cleanall& exit /b %ERRORLEVEL%
        if "%~2" == "help" call :help_help& exit /b %ERRORLEVEL%
        if ["%~2"] == [""] call :usage& exit /b %ERRORLEVEL%
        shift
    )
)

REM Compiler option
if "%~1" == "-gcc" set compiler="gcc"& set /a shift_counter+=1& shift& goto :verifyopt
if "%~1" == "-msvc" set compiler="msvc"& set /a shift_counter+=1& shift& goto :verifyopt
if "%~1" == "-tcc" set compiler="tcc"& set /a shift_counter+=1& shift& goto :verifyopt
if "%~1" == "-fresh-tcc" set compiler="fresh-tcc"& set /a shift_counter+=1& shift& goto :verifyopt
if "%~1" == "-clang" set compiler="clang"& set /a shift_counter+=1& shift& goto :verifyopt

REM Standard options
if "%~1" == "--local" (
    if !use_local! EQU 0 set /a use_local=1
    set /a shift_counter+=1
    shift
    goto :verifyopt
)
if "%~1" == "-v" (
    if !verbose_log! EQU 0 set /a verbose_log=1
    set /a shift_counter+=1
    shift
    goto :verifyopt
)
if "%~1" == "--verbose" (
    if !verbose_log! EQU 0 set /a verbose_log=1
    set /a shift_counter+=1
    shift
    goto :verifyopt
)
if "%~1" == "--logfile" (
    if ["%~2"] == [""] (
        echo Log file is not specified for -logfile parameter. 1>&2
        exit /b 2
    )
    pushd "%~dp2" 2>NUL || (
        echo The log file specified for -logfile parameter does not exist. 1>&2
        exit /b 2
    )
    popd
    set log_file="%~sf2"
    set /a shift_counter+=2
    shift
    shift
    goto :verifyopt
)
echo Undefined option: %~1
exit /b 2

:init
if !target! == "build" goto :build
if !target! == "clean" echo Cleanup build artifacts& goto :clean
if !target! == "clean-all" echo Cleanup all& goto :cleanall
if [!target!] == [""] goto :build

:build
del !log_file!>NUL 2>&1
if !use_local! NEQ 1 (
    pushd "%vc_dir%" 2>NUL&& (
        echo Updating vc...
        echo  ^> Sync with remote !vc_url!
        call :buildcmd "cd "%vc_dir%"" "  "
        call :buildcmd "git pull --quiet" "  "
        call :buildcmd "cd .." "  "
    ) || (
        echo Cloning vc...
        echo  ^> Cloning from remote !vc_url!
        call :buildcmd "git clone --depth 1 --quiet "%vc_url%"" "  "
    )
    popd
)

echo.
echo Building V...

if !compiler! == "clang" goto :clang_strap
if !compiler! == "gcc" goto :gcc_strap
if !compiler! == "msvc" goto :msvc_strap
if !compiler! == "tcc" goto :tcc_strap
if !compiler! == "fresh-tcc" goto :tcc_strap
if [!compiler!] == [""] goto :clang_strap

:clang_strap
where /q clang
if %ERRORLEVEL% NEQ 0 (
	echo  ^> Clang not found
	if not [!compiler!] == [""] goto :error
	goto :gcc_strap
)

set /a valid_cc=1

echo  ^> Attempting to build v.c with Clang
call :buildcmd "clang -std=c99 -municode -w -o v.exe .\vc\v_win.c" "  "
if %ERRORLEVEL% NEQ 0 (
	REM In most cases, compile errors happen because the version of Clang installed is too old
	call :buildcmd "clang --version" "  "
	goto :compile_error
)

echo  ^> Compiling with .\v.exe self
call :buildcmd "v.exe -cc clang self" "  "
if %ERRORLEVEL% NEQ 0 goto :compile_error
goto :success

:gcc_strap
where /q gcc
if %ERRORLEVEL% NEQ 0 (
	echo  ^> GCC not found
	if not [!compiler!] == [""] goto :error
	goto :msvc_strap
)

set /a valid_cc=1

echo  ^> Attempting to build v.c with GCC
call :buildcmd "gcc -std=c99 -municode -w -o v.exe .\vc\v_win.c" "  "
if %ERRORLEVEL% NEQ 0 (
	REM In most cases, compile errors happen because the version of GCC installed is too old
	call :buildcmd "gcc --version" "  "
	goto :compile_error
)

echo  ^> Compiling with .\v.exe self
call :buildcmd "v.exe self" "  "
if %ERRORLEVEL% NEQ 0 goto :compile_error
goto :success

:msvc_strap
set VsWhereDir=%ProgramFiles(x86)%
set HostArch=x64
if "%PROCESSOR_ARCHITECTURE%" == "x86" (
	echo Using x86 Build Tools...
	set VsWhereDir=%ProgramFiles%
	set HostArch=x86
)

if not exist "%VsWhereDir%\Microsoft Visual Studio\Installer\vswhere.exe" (
	echo  ^> MSVC not found
	if not [!compiler!] == [""] goto :error
	goto :tcc_strap
)

set /a valid_cc=1

for /f "usebackq tokens=*" %%i in (`"%VsWhereDir%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -prerelease -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
	set InstallDir=%%i
)

if exist "%InstallDir%\Common7\Tools\vsdevcmd.bat" (
	call "%InstallDir%\Common7\Tools\vsdevcmd.bat" -arch=%HostArch% -host_arch=%HostArch% -no_logo > NUL
) else if exist "%VsWhereDir%\Microsoft Visual Studio 14.0\Common7\Tools\vsdevcmd.bat" (
	call "%VsWhereDir%\Microsoft Visual Studio 14.0\Common7\Tools\vsdevcmd.bat" -arch=%HostArch% -host_arch=%HostArch% -no_logo > NUL
)

set ObjFile=.v.c.obj

echo  ^> Attempting to build v.c with MSVC
call :buildcmd "cl.exe /volatile:ms /Fo%ObjFile% /O2 /MD /D_VBOOTSTRAP vc\v_win.c user32.lib kernel32.lib advapi32.lib shell32.lib /link /nologo /out:v.exe /incremental:no" "  "
if %ERRORLEVEL% NEQ 0 goto :compile_error

echo  ^> Compiling with .\v.exe self
call :buildcmd "v.exe -cc msvc self" "  "
del %ObjFile%>>!log_file! 2>>&1
if %ERRORLEVEL% NEQ 0 goto :compile_error
goto :success

:tcc_strap
where /q tcc
if %ERRORLEVEL% NEQ 0 (
	if !compiler! == "fresh-tcc" (
        echo  ^> Clean TCC directory
        call :buildcmd "rmdir /s /q "%tcc_dir%"" "  "
        set /a valid_cc=1
    ) else if !compiler! == "tcc" set /a valid_cc=1
    if not exist %tcc_dir% (
        echo  ^> TCC not found
        echo  ^> Downloading TCC from %tcc_url%
        call :buildcmd "git clone --depth 1 --quiet "!tcc_url!" "%tcc_dir%"" "  "
    )
    pushd %tcc_dir% || (
        echo  ^> TCC not found, even after cloning
        goto :error
    )
    popd
    set "tcc_exe=%tcc_dir%\tcc.exe"
) else (
	for /f "delims=" %%i in ('where tcc') do set "tcc_exe=%%i"
    set /a valid_cc=1
)

echo  ^> Updating prebuilt TCC...
pushd "%tcc_dir%\"
call :buildcmd "git pull -q" "  "
popd

echo  ^> Attempting to build v.c with TCC
call :buildcmd ""!tcc_exe!" -std=c99 -municode -lws2_32 -lshell32 -ladvapi32 -bt10 -w -o v.exe vc\v_win.c" "  "
if %ERRORLEVEL% NEQ 0 goto :compile_error

echo  ^> Compiling with .\v.exe self
call :buildcmd "v.exe -cc "!tcc_exe!" self" "  "
if %ERRORLEVEL% NEQ 0 goto :compile_error
goto :success

:cleanall
call :clean
echo  ^> Purge TCC binaries
call :buildcmd "rmdir /s /q "%tcc_dir%"" "  "
echo  ^> Purge vc repository
call :buildcmd "rmdir /s /q "%vc_dir%"" "  "
exit /b 0

:clean
echo  ^> Purge debug symbols
call :buildcmd "del *.pdb *.lib *.bak *.out *.ilk *.exp *.obj *.o *.a *.so" "  "
echo  ^> Delete old V executable
call :buildcmd "del v_old.exe v*.exe" "  "
exit /b 0

:compile_error
echo.
type !log_file!>NUL 2>&1
goto :error

:error
echo.
echo Exiting from error
exit /b 1

:success
echo  ^> V built successfully!
echo  ^> To add V to your PATH, run `.\v.exe symlink`.
if !valid_cc! EQU 0 (
    echo.
    echo WARNING:  No C compiler was detected in your PATH. `tcc` was used temporarily
    echo           to build V, but it may have some bugs and may not work in all cases.
    echo           A more advanced C compiler like GCC or MSVC is recommended.
    echo           https://github.com/vlang/v/wiki/Installing-a-C-compiler-on-Windows
    echo.
)

del v_old.exe>>!log_file! 2>NUL
del !log_file! 2>NUL

:version
echo.
echo | set /p="V version: "
.\v.exe version
goto :eof

:buildcmd
if !verbose_log! EQU 1 (
    echo [Debug] %~1>>!log_file!
    echo %~2 %~1
)
%~1>>!log_file! 2>>&1
exit /b %ERRORLEVEL%

:usage
echo.
echo Usage:
echo     make.bat [target] [compiler] [options]
echo.
echo Compiler:
echo     -msvc ^| -gcc ^| -[fresh-]tcc ^| -clang    Set C compiler
echo.
echo Target:
echo    build[default]                    Compiles V using the given C compiler
echo    clean                             Clean build artifacts and debugging symbols
echo    clean-all                         Cleanup entire ALL build artifacts and vc repository
echo    help                              Display usage help for the given target
echo.
echo Examples:
echo     make.bat -msvc
echo     make.bat -gcc --local --logpath output.log
echo     make.bat build -fresh-tcc --local
echo     make.bat help clean
echo.
echo Use "make help <target>" for more information about a target, for instance: "make help clean"
echo.
echo Note: Any undefined options will cause an error
exit /b 0

:help_help
echo Usage:
echo     make.bat help [target]
echo.
echo Target:
echo     build ^| clean ^| clean-all ^| help    Query given target
exit /b 0

:help_clean
echo Usage:
echo     make.bat clean
echo.
echo Options:
echo    --logfile PATH                    Use the specified PATH as the log
echo    -v ^| --verbose                    Output compilation commands to stdout
exit /b 0

:help_cleanall
echo Usage:
echo     make.bat clean-all
echo.
echo Options:
echo    --logfile PATH                    Use the specified PATH as the log
echo    -v ^| --verbose                    Output compilation commands to stdout
exit /b 0

:help_build
echo Usage:
echo     make.bat build [compiler] [options]
echo.
echo Compiler:
echo     -msvc ^| -gcc ^| -[fresh-]tcc ^| -clang    Set C compiler
echo.
echo Options:
echo    --local                           Use the local vc repository without
echo                                      syncing with remote
echo    --logfile PATH                    Use the specified PATH as the log
echo                                      file
echo    -v ^| --verbose                    Output compilation commands to stdout
exit /b 0

:eof
popd
endlocal
exit /b 0