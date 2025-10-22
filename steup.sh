#!/bin/bash
set -e #Causa que en caso de error el script pare

# Verificar que se ejecute como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta el script como sudo:"
    echo "sudo ./setup.sh"
    exit 1
fi

#Variables
OCTO_PATH="/opt/OctoPrint"
USER_NAME="${SUDO_USER:-$USER}"  # Detecta el usuario real, incluso si se ejecuta con sudo
SHARE_DIR="/home/$USER_NAME/sambashare"

#Cosas Importantes
sudo systemctl enable ssh
sudo systemctl start ssh

echo "Actualizando sistema"
sudo apt update -y
sudo apt upgrade -y

echo "---------------------------------------------------------"
if ! command -v tailscale >/dev/null
then
        echo "Instalando Tailscale..."
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
        sudo apt update -y
        sudo apt install -y tailscale
        echo "Ahora se le pedira iniciar sesion en tu cuenta de tailscale"
        sudo tailscale up
else
        echo "Tailscale ya esta instalado"
fi


echo "---------------------------------------------------------"
echo "Instalando Octoprint..."
if [ ! -f "${OCTO_PATH}/bin/octoprint" ]; then
        mkdir -p "$OCTO_PATH"
        chown "$USER_NAME":"$USER_NAME" "$OCTO_PATH"
        sudo apt install python3 python3-venv python3-pip build-essential
        python3 -m venv  "${OCTO_PATH}"
        "${OCTO_PATH}/bin/pip" install --upgrade pip
        "${OCTO_PATH}/bin/pip" install OctoPrint
        sudo usermod -a -G tty $USER_NAME
        sudo usermod -a -G dialout $USER_NAME

        sudo tee /etc/systemd/system/octoprint.service > /dev/null <<EOF
        [Unit]
        Description=OctoPrint Daemon
        After=network.target

        [Service]
        Type=simple
        User=$USER_NAME
        ExecStart=${OCTO_PATH}/bin/octoprint serve
        WorkingDirectory=$OCTO_PATH
        Restart=always

        [Install]
        WantedBy=multi-user.target
        EOF

        sudo systemctl daemon-reload
        sudo systemctl enable octoprint
        sudo systemctl start octoprint
        echo "OctoPrint instalado"
else
        echo "Octoprint ya esta instalado"

#-------------------------      CASA_OS         ------------------------
echo "-------------------------------------------"
if ! command -v casaos >/dev/null; then
    echo "Instalando CasaOS..."
    curl -fsSL https://get.casaos.io | bash
else
    echo "CasaOS ya está instalado"
fi

#-----------------------        SAMBA           ------------------------
echo "--------------------------------------------"
echo "Instalando Samba..."
apt install -y samba
mkdir -p "$SHARE_DIR"
chown "$USER_NAME:$USER_NAME" "$SHARE_DIR"
chmod 755 "$SHARE_DIR"

# Backup de configuración original
cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

cat <<EOF >> /etc/samba/smb.conf
[sambashare]
    comment = Samba on Ubuntu
    path = /home/${USER_NAME}/sambashare
    read only = no
    browsable = yes
    guest ok = yes
    create mask 0755
EOF
ufw allow samba
echo "Configure su contraseña para el usuario: $USER_NAME"
smbpasswd -a "$USER_NAME"
systemctl restart smbd.service nmbd.service
echo "---> La carpeta compartida está en: $SHARE_DIR <---"
echo "---> Puedes acceder desde otro dipositivo en:  //machine_ip/sambashare <---"
echo ""

echo "========================================================="
echo "INSTALACIÓN COMPLETADA"
echo "========================================================="
echo "Servicios instalados:"
echo "• SSH: Acceso remoto (puerto 22)"
echo "• OctoPrint: http://$(hostname -I | awk '{print $1}'):5000"
echo "• CasaOS: http://$(hostname -I | awk '{print $1}')"
echo "• Samba: //$(hostname -I | awk '{print $1}')/sambashare"
echo "• Tailscale: Red VPN instalada"
echo ""
echo "Carpeta compartida: $SHARE_DIR"
echo "Usuario del sistema: $USER_NAME"
echo "========================================================="