# Guía en Español

Esta guía explica cómo crear un nuevo sitio web usando esta base y los proyectos de [Docker](https://derafu.org/docker-php-caddy-server) y [Fabric]() para el desarrollo local y despliegue en el servidor de producción.

[TOC]

## Revisa lo que necesitas hacer, instalar o saber

### Configurar ZSH en equipo local macOS

Si estás en macOS y usas ZSH como shell, puedes configurar ZSH para que acepte comentarios comandos con:

```shell
echo "setopt interactivecomments" >> ~/.zshrc
source ~/.zshrc
```

### Clave SSH en equipo local

Es necesario tener una clave SSH en el equipo local, esta clave será utilizada para configurar tu contenedor Docker.

Con el siguiente comando se obtiene una clave preexistente o se crea una nueva en `$HOME/.ssh/id_rsa` y `$HOME/.ssh/id_rsa.pub`. Si se crea una nueva deberás ingresar el correo para identificar al usuario dueño de la clave. Si lo prefieres, puedes ingresar tu usuario y nombre de equipo (en caso que tengas múltiples claves SSH en diferentes ambientes).

```shell
SSH_KEY="$HOME/.ssh/id_rsa"
if [ -f "$SSH_KEY.pub" ]; then
    cat "$SSH_KEY.pub"
else
    echo -n "Ingresa tu correo: "; read COMMENT
    ssh-keygen -t rsa -b 4096 -N "" -C "$COMMENT" -f "$SSH_KEY"
    cat "$SSH_KEY.pub"
fi
```

Con este comando la clave pública será mostrada en pantalla. Si la necesitas volver a ver en el futuro ejecuta:

```shell
cat $HOME/.ssh/id_rsa.pub
```

**Importante**: La clave en `$HOME/.ssh/id_rsa` es **privada** y jamás debe ser compartida.

### Agregar clave SSH a GitHub

1. Ir a [GitHub](https://github.com/settings/ssh/new).
2. En `Title` ingresar lo mismo que hayas elegido como correo o comentario de la clave al crearla.
3. En `Key` pegar la clave pública extraída con `cat $HOME/.ssh/id_rsa.pub`.
4. Haz click en `Add SSH key`.

### Contenedor Docker con Python y Caddy

Preparar [Docker](https://derafu.org/docker-php-caddy-server) en `$DOCKER_DIR` en el equipo local:

```shell
DEV_DIR=$HOME/dev
DOCKER_DIR=$DEV_DIR/docker-sites-php
mkdir -p $DEV_DIR
git clone https://github.com/derafu/docker-php-caddy-server.git $DOCKER_DIR
cat $HOME/.ssh/id_rsa.pub > $DOCKER_DIR/config/ssh/authorized_keys
cd $DOCKER_DIR
```

Copiar y editar el archivo `.env` y configurar las variables de entorno según sea necesario.

```shell
cp .env-dist .env
```

{.alert .alert-warning .my-3}
<i class="fa fa-exclamation-triangle fa-fw me-2"></i>
No avances hasta haber revisado y configurado el archivo `.env`.

Construir el contenedor Docker:

```shell
docker-compose up -d
```

Con esta configuración quedará en `$DOCKER_DIR/sites` la carpeta donde se instalarán los sitios a desarrollar. Esta carpeta estará compartida entre el equipo local y el contenedor Docker.

### Conectar al contenedor Docker

Configura el alias `dev` de SSH en tu equipo local:

```shell
echo "
Host dev
    HostName localhost
    User admin
    Port 2222
    IdentityFile $HOME/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
" >> $HOME/.ssh/config
```

Luego puedes ingresar al contenedor Docker con:

```shell
ssh dev
```

**Nota**: El nombre del alias puede ser el que quieras, en este caso se usó `dev`.

### Clave SSH en el contenedor Docker

Para trabajar con repositorios privados y hacer deploy al servidor de producción, es necesario que la clave SSH en el equipo local sea agregada al contenedor Docker.

En tu equipo local, ejecuta:

```shell
scp $HOME/.ssh/id_rsa* dev:.ssh/
```

### Configuración básica de Git

Realiza las siguientes configuraciones dentro del contenedor Docker.

Primero, configurar tu correo y nombre de GitHub:

{.alert .alert-warning .my-3}
<i class="fa fa-exclamation-triangle fa-fw me-2"></i>
Antes de pegar este comando en el contenedor Docker, edítalo para que use tu correo y nombre de GitHub.

```shell
git config --global user.email "you@example.com"  # Your github email.
git config --global user.name "Your Name"         # Your name.
```

Configurar sensibilidad a mayúsculas/minúsculas y evitar mezclas de cambios:

```shell
git config --global core.ignorecase false         # Case sensitive.
git config --global pull.rebase false             # Rebase instead of merge.
git config --global merge.ff false                # Fast forward.
```

Configurar editor de texto:

```shell
git config --global core.editor nano              # Default editor nano or any other.
```

### Configurar firma de commits en Git

Primero, crear la clave SSH en el equipo local:

```shell
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ -f "$SSH_KEY.pub" ]; then
    cat "$SSH_KEY.pub"
else
    echo -n "Ingresa tu correo: "; read COMMENT
    ssh-keygen -t ed25519 -N "" -C "$COMMENT" -f "$SSH_KEY"
    cat "$SSH_KEY.pub"
fi
```

Luego agregar la clave SSH al contenedor Docker:

```shell
scp $HOME/.ssh/id_ed25519* dev:.ssh/
```

Finalmente, dentro del contenedor Docker configura Git para firmar commits:

```shell
git config --global commit.gpgSign true               # Sign commits.
git config --global user.signingkey ~/.ssh/id_ed25519 # Your ssh key.
git config --global gpg.format ssh                    # Use ssh key.
git config --global tag.gpgSign true                  # Sign tags.
```

## Desarrolla un sitio web

### Crear un nuevo sitio web

Ingresar al contenedor y ejecuta:

```shell
site-create www.example.com
```

**Nota**: Crear el sitio web requiere como paso posterior que configures su repositorio en GitHub y que agregues el sitio en el archivo `$DEPLOYER_DIR/sites.php` usando el comando `site-add`.

### Clonar un sitio web

Ingresar al contenedor y ejecuta:

```shell
site-clone www.example.com git@github.com:example/example.git
```

**Nota**: Al clonar un sitio web existente automáticamente se agrega el sitio en el archivo `$DEPLOYER_DIR/sites.php`.

### Visitar el sitio web en el navegador

En tu equipo configura `/etc/hosts` agregando el dominio de desarrollo local:

```shell
echo "127.0.0.1         www.example.com.local" | sudo tee -a /etc/hosts
```

Luego podrás acceder al sitio web mediante la URL https://www.example.com.local:8443

## Despliega un sitio web a producción

Todas estas instrucciones se ejecutan en el contenedor Docker.

### Agregar sitio web en el archivo de configuración

Si creaste el sitio de 0 en vez de clonarlo, asegurate de que el sitio web esté agregado en el archivo `$DEPLOYER_DIR/sites.php`. Puedes validar esto ejecutando:

```shell
site-add www.example.com git@github.com:example/example.git
```

**Nota**: Si el sitio requiere una configuración especial deberás editar manualmente el archivo `$DEPLOYER_DIR/sites.php`.

### Pruebas de estilo, calidad de código y pruebas unitarias

Realiza pruebas de estilo, calidad de código y pruebas unitarias en el contenedor Docker con:

```shell
site www.example.com
site-check
```

### Subir cambios a GitHub

Si todo está correcto sube los cambios a GitHub:

```shell
site www.example.com
site-send "Actualización de sitio web."
```

**Nota**: Si el repositorio en GitHub tiene [configurado un webhook](https://derafu.org/github), el sitio web se desplegará automáticamente al subir los cambios y pasar las pruebas de estilo, calidad de código y pruebas unitarias en el workflow de GitHub Actions.

### Despliegue

{.alert .alert-info .my-3}
<i class="fa fa-info-circle fa-fw me-2"></i>
No es necesario hacer deploy al servidor de producción si el repositorio en GitHub tiene [configurado un webhook](https://derafu.org/github){.alert-link}.

Si no hay errores, puedes hacer deploy al servidor de producción con:

```shell
#DEPLOYER_HOST=hosting.example.com # Solo si no se configuró en .env
site-deploy www.example.com
```

Si ocurre algún error al hacer el deploy y tratas de hacer un deploy nuevo, es muy probable que el deploy esté bloqueado. Si esto sucede, puedes desbloquear y hacer deploy nuevamente con:

```shell
#DEPLOYER_HOST=hosting.example.com # Solo si no se configuró en .env
site-deploy-locked www.example.com
```

## Actualiza componentes

### Actualizar Docker

En tu equipo local, ejecuta:

```shell
DEV_DIR=$HOME/dev
DOCKER_DIR=$DEV_DIR/docker-sites-php
cd $DOCKER_DIR
git pull
docker-compose build --no-cache
docker-compose up -d
```

{.alert .alert-warning .my-3}
<i class="fa fa-exclamation-triangle fa-fw me-2"></i>
Debes volver a agregar las claves SSH al contenedor Docker y configurar Git dentro del contenedor.

### Actualizar PHP Deployer

Ingresa al contenedor y ejecuta:

```shell
cd $DEPLOYER_DIR
git pull
composer update
```

### Actualizar sitio web

Ingresar al contenedor y ejecuta:

```shell
site www.example.com
site-update
```

## Uso de herramientas de desarrollo

### Git

Ver el estado de los cambios:

```shell
git status
```

Agregar cambios:

```shell
git add .
```

Hacer commit:

```shell
git commit -m "Mensaje del commit"
```

Subir cambios a GitHub:

```shell
git push
```

Actualizar repositorio local:

```shell
git pull
```

Deshacer cambios:

```shell
git checkout -- .
```

**Nota**: En vez de utilizar punto `.` puedes especificar los archivos que deseas agregar, hacer commit o revertir.


## Uso de terminal en el contenedor Docker

Ingresar al directorio de un sitio web:

```shell
cd $SITES_DIR/www.example.com
```

Salir del directorio:

```shell
cd ..
```

Listar archivos:

```shell
ls -la
```

Ver contenido de un archivo:

```shell
cat $DEPLOYER_DIR/sites.php
```

Editar un archivo:

```shell
nano $DEPLOYER_DIR/sites.php
```

Guardar y salir en `nano`:

```shell
Ctrl + X
```
