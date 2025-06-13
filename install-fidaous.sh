#!/bin/bash

# Fidaous Pro - Script d'installation automatisée
# Compatible avec Debian 12
# Version 1.0

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration par défaut
DB_NAME="database_fidaous_pro"
DB_USER="fidaous_user"
DB_PASSWORD=""
MYSQL_ROOT_PASSWORD=""
WEB_USER="www-data"
WEB_DIR="/var/www/fidaous-pro"
DOMAIN_NAME=""
PHP_VERSION="8.2"

# Fonction d'affichage
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Vérifier les privilèges root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté en tant que root (sudo)"
    fi
}

# Vérifier la version de Debian
check_debian_version() {
    if ! grep -q "Debian GNU/Linux 12" /etc/os-release; then
        print_warning "Ce script est optimisé pour Debian 12. Continuer quand même ? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Collecter les informations de configuration
collect_config() {
    echo -e "${BLUE}=== Configuration de l'installation ===${NC}"
    
    # Mot de passe root MySQL
    while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
        echo -n "Mot de passe root MySQL (sera créé si MySQL n'est pas installé): "
        read -s MYSQL_ROOT_PASSWORD
        echo
    done
    
    # Mot de passe base de données
    while [[ -z "$DB_PASSWORD" ]]; do
        echo -n "Mot de passe pour l'utilisateur base de données '$DB_USER': "
        read -s DB_PASSWORD
        echo
    done
    
    # Nom de domaine (optionnel pour SSL)
    echo -n "Nom de domaine (optionnel, pour SSL): "
    read -r DOMAIN_NAME
    
    echo -e "${GREEN}Configuration collectée avec succès${NC}"
}

# Mise à jour du système
update_system() {
    print_status "Mise à jour du système..."
    apt-get update -qq
    apt-get upgrade -y -qq
    print_success "Système mis à jour"
}

# Installation des dépendances système
install_dependencies() {
    print_status "Installation des dépendances système..."
    
    # Paquets de base
    apt-get install -y -qq \
        curl \
        wget \
        unzip \
        git \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    
    print_success "Dépendances système installées"
}

# Installation et configuration de MariaDB
install_mariadb() {
    print_status "Installation de MariaDB..."
    
    # Installation
    apt-get install -y -qq mariadb-server mariadb-client
    
    # Démarrage et activation
    systemctl start mariadb
    systemctl enable mariadb
    
    # Configuration sécurisée
    print_status "Configuration sécurisée de MariaDB..."
    
    # Script de sécurisation automatique
    mysql -e "UPDATE mysql.user SET Password = PASSWORD('${MYSQL_ROOT_PASSWORD}') WHERE User = 'root'"
    mysql -e "DELETE FROM mysql.user WHERE User=''"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    mysql -e "DROP DATABASE IF EXISTS test"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test_%'"
    mysql -e "FLUSH PRIVILEGES"
    
    # Création de la base de données et utilisateur
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}'"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'"
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES"
    
    print_success "MariaDB installé et configuré"
}

# Installation de PHP et extensions
install_php() {
    print_status "Installation de PHP ${PHP_VERSION} et extensions..."
    
    # Ajout du dépôt Sury pour PHP
    wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    apt-get update -qq
    
    # Installation PHP et modules
    apt-get install -y -qq \
        php${PHP_VERSION} \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-json \
        php${PHP_VERSION}-readline \
        php${PHP_VERSION}-opcache
    
    # Configuration PHP
    sed -i 's/;date.timezone =/date.timezone = Europe\/Paris/' /etc/php/${PHP_VERSION}/fpm/php.ini
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' /etc/php/${PHP_VERSION}/fpm/php.ini
    sed -i 's/post_max_size = 8M/post_max_size = 100M/' /etc/php/${PHP_VERSION}/fpm/php.ini
    sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/${PHP_VERSION}/fpm/php.ini
    sed -i 's/memory_limit = 128M/memory_limit = 512M/' /etc/php/${PHP_VERSION}/fpm/php.ini
    
    # Démarrage PHP-FPM
    systemctl start php${PHP_VERSION}-fpm
    systemctl enable php${PHP_VERSION}-fpm
    
    print_success "PHP ${PHP_VERSION} installé et configuré"
}

# Installation et configuration de Nginx
install_nginx() {
    print_status "Installation de Nginx..."
    
    apt-get install -y -qq nginx
    
    # Configuration du site
    cat > /etc/nginx/sites-available/fidaous-pro << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME:-localhost};
    root ${WEB_DIR};
    index index.php index.html;

    # Logs
    access_log /var/log/nginx/fidaous-pro-access.log;
    error_log /var/log/nginx/fidaous-pro-error.log;

    # PHP processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    # API routes
    location /api/ {
        try_files \$uri \$uri/ /api/endpoints.php?\$query_string;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
    
    location ~ /(config|classes|utils)/ {
        deny all;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Activer le site
    ln -sf /etc/nginx/sites-available/fidaous-pro /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test de la configuration
    nginx -t
    
    # Démarrage Nginx
    systemctl start nginx
    systemctl enable nginx
    
    print_success "Nginx installé et configuré"
}

# Création de la structure de l'application
create_app_structure() {
    print_status "Création de la structure de l'application..."
    
    # Création du répertoire web
    mkdir -p "${WEB_DIR}"
    mkdir -p "${WEB_DIR}/api"
    mkdir -p "${WEB_DIR}/config"
    mkdir -p "${WEB_DIR}/classes"
    mkdir -p "${WEB_DIR}/utils"
    mkdir -p "${WEB_DIR}/uploads"
    mkdir -p "${WEB_DIR}/logs"
    mkdir -p "${WEB_DIR}/assets/css"
    mkdir -p "${WEB_DIR}/assets/js"
    mkdir -p "${WEB_DIR}/assets/images"
    
    print_success "Structure de l'application créée"
}

# Installation des fichiers de l'application
install_app_files() {
    print_status "Installation des fichiers de l'application..."
    
    # Création du fichier de configuration de base de données
    cat > "${WEB_DIR}/config/database.php" << 'EOF'
<?php
// config/database.php - Configuration de la base de données
class Database {
    private $host = 'localhost';
    private $db_name = 'database_fidaous_pro';
    private $username = 'fidaous_user';
    private $password = '';
    private $charset = 'utf8mb4';
    public $pdo;

    public function getConnection() {
        $this->pdo = null;
        try {
            $dsn = "mysql:host=" . $this->host . ";dbname=" . $this->db_name . ";charset=" . $this->charset;
            $options = [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
            ];
            $this->pdo = new PDO($dsn, $this->username, $this->password, $options);
        } catch(PDOException $exception) {
            echo "Erreur de connexion: " . $exception->getMessage();
        }
        return $this->pdo;
    }
}
EOF

    # Mise à jour des paramètres de base de données
    sed -i "s/private \$password = '';/private \$password = '${DB_PASSWORD}';/" "${WEB_DIR}/config/database.php"
    
    # Page d'accueil simple
    cat > "${WEB_DIR}/index.php" << 'EOF'
<?php
session_start();
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fidaous Pro - Gestion Cabinet</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; }
        .header h1 { color: #2c3e50; margin: 0; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-top: 30px; }
        .status-card { background: #ecf0f1; padding: 20px; border-radius: 6px; text-align: center; }
        .status-card.success { background: #d5f4e6; border-left: 4px solid #27ae60; }
        .status-card.error { background: #fadbd8; border-left: 4px solid #e74c3c; }
        .btn { display: inline-block; padding: 12px 24px; background: #3498db; color: white; text-decoration: none; border-radius: 4px; margin: 10px; }
        .btn:hover { background: #2980b9; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏢 Fidaous Pro</h1>
            <p>Système de gestion pour cabinet comptable</p>
        </div>
        
        <div class="status-grid">
            <div class="status-card success">
                <h3>✅ Installation Réussie</h3>
                <p>L'application a été installée avec succès</p>
            </div>
            
            <div class="status-card">
                <h3>🔧 Configuration</h3>
                <p>Vérifiez les paramètres dans le fichier config/database.php</p>
            </div>
            
            <div class="status-card">
                <h3>📊 Base de données</h3>
                <p>Schéma créé automatiquement</p>
            </div>
        </div>
        
        <div style="text-align: center; margin-top: 30px;">
            <a href="/api/endpoints.php" class="btn">Tester l'API</a>
            <a href="/install/setup.php" class="btn">Configuration avancée</a>
        </div>
        
        <div style="margin-top: 30px; padding: 20px; background: #f8f9fa; border-radius: 4px;">
            <h3>Prochaines étapes :</h3>
            <ol>
                <li>Configurer les paramètres dans config/database.php si nécessaire</li>
                <li>Créer le premier utilisateur administrateur</li>
                <li>Configurer les types de dossiers et rôles</li>
                <li>Tester les fonctionnalités de base</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF

    print_success "Fichiers de l'application installés"
}

# Création du schéma de base de données
create_database_schema() {
    print_status "Création du schéma de base de données..."
    
    # Script SQL pour créer les tables
    cat > /tmp/fidaous_schema.sql << 'EOF'
-- Fidaous Pro - Schéma de base de données
SET FOREIGN_KEY_CHECKS = 0;

-- Table des rôles
CREATE TABLE IF NOT EXISTS roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    permissions JSON,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Table des employés
CREATE TABLE IF NOT EXISTS employes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    matricule VARCHAR(20) NOT NULL UNIQUE,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    telephone VARCHAR(20),
    cin VARCHAR(20),
    mot_de_passe VARCHAR(255) NOT NULL,
    role_id INT,
    date_embauche DATE,
    salaire DECIMAL(10,2),
    status ENUM('Actif', 'Inactif', 'Suspendu') DEFAULT 'Actif',
    derniere_connexion TIMESTAMP NULL,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id)
);

-- Table des clients
CREATE TABLE IF NOT EXISTS clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code_client VARCHAR(20) UNIQUE,
    raison_sociale VARCHAR(255) NOT NULL,
    forme_juridique ENUM('SARL', 'SA', 'SAS', 'EURL', 'SNC', 'Auto-entrepreneur', 'Association', 'Autre') NOT NULL,
    ice VARCHAR(15),
    rc VARCHAR(50),
    patente VARCHAR(50),
    cnss VARCHAR(50),
    regime_fiscal ENUM('Réel', 'Forfaitaire', 'Auto-entrepreneur') DEFAULT 'Réel',
    activite_principale TEXT,
    adresse_siege TEXT,
    ville_siege VARCHAR(100),
    telephone_fixe VARCHAR(20),
    telephone_mobile VARCHAR(20),
    email VARCHAR(255),
    employe_responsable INT,
    status ENUM('Actif', 'Inactif', 'Suspendu') DEFAULT 'Actif',
    -- Informations personne physique (pour auto-entrepreneurs)
    personne_cin VARCHAR(20),
    personne_nom VARCHAR(100),
    personne_prenom VARCHAR(100),
    personne_date_naissance DATE,
    personne_lieu_naissance VARCHAR(100),
    -- Informations plateformes
    dgi_login VARCHAR(100),
    dgi_password TEXT,
    dgi_numero_contribuable VARCHAR(50),
    damancom_login VARCHAR(100),
    damancom_password TEXT,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (employe_responsable) REFERENCES employes(id),
    INDEX idx_ice (ice),
    INDEX idx_raison_sociale (raison_sociale)
);

-- Table des types de dossiers
CREATE TABLE IF NOT EXISTS types_dossiers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(150) NOT NULL,
    categorie ENUM('Comptabilité', 'Fiscal', 'Social', 'Juridique', 'Conseil') NOT NULL,
    description TEXT,
    duree_standard_jours INT DEFAULT 30,
    modele_documents JSON,
    status ENUM('Actif', 'Inactif') DEFAULT 'Actif',
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table des dossiers
CREATE TABLE IF NOT EXISTS dossiers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    numero_dossier VARCHAR(50) UNIQUE,
    client_id INT NOT NULL,
    type_dossier_id INT NOT NULL,
    exercice_fiscal YEAR,
    date_ouverture DATE NOT NULL,
    date_echeance DATE NOT NULL,
    employe_responsable INT,
    employe_createur INT,
    status ENUM('Ouvert', 'En cours', 'En attente', 'Terminé', 'Annulé', 'Archivé') DEFAULT 'Ouvert',
    priorite ENUM('Basse', 'Normale', 'Haute', 'Urgente') DEFAULT 'Normale',
    montant_honoraires DECIMAL(10,2) DEFAULT 0,
    observations TEXT,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(id),
    FOREIGN KEY (type_dossier_id) REFERENCES types_dossiers(id),
    FOREIGN KEY (employe_responsable) REFERENCES employes(id),
    FOREIGN KEY (employe_createur) REFERENCES employes(id),
    INDEX idx_client_exercice (client_id, exercice_fiscal),
    INDEX idx_status_echeance (status, date_echeance)
);

-- Table des tâches
CREATE TABLE IF NOT EXISTS taches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    numero_tache VARCHAR(50) UNIQUE,
    titre VARCHAR(255) NOT NULL,
    description TEXT,
    dossier_id INT,
    employe_assigne INT NOT NULL,
    employe_createur INT NOT NULL,
    date_creation DATE NOT NULL,
    date_echeance DATE NOT NULL,
    date_completion TIMESTAMP NULL,
    status ENUM('À faire', 'En cours', 'En pause', 'Terminée', 'Annulée') DEFAULT 'À faire',
    priorite ENUM('Basse', 'Normale', 'Haute', 'Urgente') DEFAULT 'Normale',
    temps_estime_heures DECIMAL(5,2) DEFAULT 0,
    temps_reel_heures DECIMAL(5,2) DEFAULT 0,
    pourcentage_avancement INT DEFAULT 0,
    commentaires TEXT,
    date_creation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (dossier_id) REFERENCES dossiers(id),
    FOREIGN KEY (employe_assigne) REFERENCES employes(id),
    FOREIGN KEY (employe_createur) REFERENCES employes(id),
    INDEX idx_employe_status (employe_assigne, status),
    INDEX idx_echeance (date_echeance)
);

-- Table des échéances
CREATE TABLE IF NOT EXISTS echeances (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type_echeance ENUM('Dossier', 'Déclaration', 'Paiement', 'Réunion', 'Autre') NOT NULL,
    reference_id INT,
    titre VARCHAR(255) NOT NULL,
    description TEXT,
    date_echeance DATETIME NOT NULL,
    employe_responsable INT,
    status ENUM('Active', 'Terminée', 'Reportée', 'Annulée') DEFAULT 'Active',
    alerte_1_jours INT DEFAULT 7,
    alerte_2_jours INT DEFAULT 3,
    alerte_3_jours INT DEFAULT 1,
    alerte_1_envoyee BOOLEAN DEFAULT FALSE,
    alerte_2_envoyee BOOLEAN DEFAULT FALSE,
    alerte_3_envoyee BOOLEAN DEFAULT FALSE,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employe_responsable) REFERENCES employes(id),
    INDEX idx_date_status (date_echeance, status)
);

-- Table des documents
CREATE TABLE IF NOT EXISTS documents (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom_fichier VARCHAR(255) NOT NULL,
    nom_original VARCHAR(255) NOT NULL,
    type_document ENUM('Contrat', 'Facture', 'Déclaration', 'Rapport', 'Correspondance', 'Autre') DEFAULT 'Autre',
    chemin_fichier TEXT NOT NULL,
    nextcloud_path TEXT,
    nextcloud_file_id VARCHAR(100),
    taille_fichier BIGINT,
    client_id INT,
    dossier_id INT,
    tache_id INT,
    upload_par INT,
    date_upload TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(id),
    FOREIGN KEY (dossier_id) REFERENCES dossiers(id),
    FOREIGN KEY (tache_id) REFERENCES taches(id),
    FOREIGN KEY (upload_par) REFERENCES employes(id),
    INDEX idx_client_type (client_id, type_document)
);

-- Table des logs d'activités
CREATE TABLE IF NOT EXISTS activites_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employe_id INT NOT NULL,
    type_activite ENUM('Connexion', 'Création', 'Modification', 'Suppression', 'Consultation', 'Notification') NOT NULL,
    module VARCHAR(50) NOT NULL,
    table_concernee VARCHAR(50),
    enregistrement_id INT,
    description TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    date_activite TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employe_id) REFERENCES employes(id),
    INDEX idx_employe_date (employe_id, date_activite),
    INDEX idx_module_date (module, date_activite)
);

-- Table des paramètres système
CREATE TABLE IF NOT EXISTS parametres_systeme (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cle_parametre VARCHAR(100) NOT NULL UNIQUE,
    valeur TEXT,
    description TEXT,
    type_parametre ENUM('string', 'number', 'boolean', 'json', 'encrypted') DEFAULT 'string',
    date_modification TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Table conversations WhatsApp
CREATE TABLE IF NOT EXISTS whatsapp_conversations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id INT,
    employe_id INT NOT NULL,
    numero_client VARCHAR(20) NOT NULL,
    nom_contact VARCHAR(255),
    status ENUM('Active', 'Fermée', 'Archivée') DEFAULT 'Active',
    derniere_activite TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(id),
    FOREIGN KEY (employe_id) REFERENCES employes(id),
    INDEX idx_numero_status (numero_client, status)
);

-- Table messages WhatsApp
CREATE TABLE IF NOT EXISTS whatsapp_messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    conversation_id INT NOT NULL,
    message_id_whatsapp VARCHAR(255),
    type_message ENUM('text', 'image', 'document', 'audio', 'video', 'template') NOT NULL,
    contenu TEXT,
    media_url TEXT,
    direction ENUM('entrant', 'sortant') NOT NULL,
    status_message ENUM('envoyé', 'livré', 'lu', 'échoué') DEFAULT 'envoyé',
    envoye_par INT,
    timestamp_whatsapp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    date_creation TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (conversation_id) REFERENCES whatsapp_conversations(id),
    FOREIGN KEY (envoye_par) REFERENCES employes(id),
    INDEX idx_conversation_date (conversation_id, timestamp_whatsapp)
);

-- Insertion des données de base
INSERT INTO roles (nom, description, permissions) VALUES 
('Administrateur', 'Accès complet au système', '["all"]'),
('Comptable Senior', 'Gestion complète des dossiers', '["clients", "dossiers", "taches", "documents", "rapports"]'),
('Comptable Junior', 'Gestion limitée des dossiers', '["dossiers_read", "taches", "documents_read"]'),
('Assistant', 'Consultation et saisie de base', '["clients_read", "dossiers_read", "taches_read"]');

INSERT INTO types_dossiers (nom, categorie, description, duree_standard_jours) VALUES 
('Déclaration TVA Mensuelle', 'Fiscal', 'Déclaration de TVA mensuelle', 7),
('Bilan Comptable Annuel', 'Comptabilité', 'Établissement du bilan annuel', 45),
('Déclaration IS', 'Fiscal', 'Déclaration Impôt sur les Sociétés', 30),
('Liasse Fiscale', 'Fiscal', 'Préparation de la liasse fiscale', 30),
('Révision Comptable', 'Comptabilité', 'Révision des comptes', 15),
('Déclaration CNSS', 'Social', 'Déclaration CNSS mensuelle', 10);

INSERT INTO parametres_systeme (cle_parametre, valeur, description, type_parametre) VALUES 
('version_application', '1.0.0', 'Version de l\'application', 'string'),
('timezone', 'Africa/Casablanca', 'Fuseau horaire', 'string'),
('langue_defaut', 'fr', 'Langue par défaut', 'string'),
('email_notifications', 'true', 'Activer les notifications email', 'boolean'),
('nextcloud_url', '', 'URL du serveur Nextcloud', 'string'),
('nextcloud_username', '', 'Nom d\'utilisateur Nextcloud', 'string'),
('nextcloud_password', '', 'Mot de passe Nextcloud (crypté)', 'encrypted'),
('nextcloud_base_folder', 'FidaousPro', 'Dossier de base dans Nextcloud', 'string'),
('whatsapp_business_phone_id', '', 'ID du numéro WhatsApp Business', 'string'),
('whatsapp_access_token', '', 'Token d\'accès WhatsApp', 'encrypted'),
('whatsapp_verify_token', '', 'Token de vérification webhook', 'string');

-- Vues pour les statistiques
CREATE OR REPLACE VIEW vue_dossiers_en_retard AS
SELECT 
    d.*,
    c.raison_sociale,
    c.code_client,
    td.nom as type_dossier_nom,
    CONCAT(e.prenom, ' ', e.nom) as responsable_nom,
    DATEDIFF(CURDATE(), d.date_echeance) as jours_retard
FROM dossiers d
JOIN clients c ON d.client_id = c.id
JOIN types_dossiers td ON d.type_dossier_id = td.id
LEFT JOIN employes e ON d.employe_responsable = e.id
WHERE d.date_echeance < CURDATE() 
AND d.status NOT IN ('Terminé', 'Annulé', 'Archivé');

CREATE OR REPLACE VIEW vue_taches_par_employe AS
SELECT 
    e.id as employe_id,
    CONCAT(e.prenom, ' ', e.nom) as employe_nom,
    COUNT(CASE WHEN t.status = 'À faire' THEN 1 END) as taches_a_faire,
    COUNT(CASE WHEN t.status = 'En cours' THEN 1 END) as taches_en_cours,
    COUNT(CASE WHEN t.status = 'Terminée' THEN 1 END) as taches_terminees,
    COUNT(*) as total_taches,
    AVG(CASE WHEN t.status = 'Terminée' AND t.temps_reel_heures > 0 THEN t.temps_reel_heures END) as temps_moyen_reel,
    AVG(CASE WHEN t.status = 'Terminée' AND t.temps_estime_heures > 0 THEN t.temps_estime_heures END) as temps_moyen_estime
FROM employes e
LEFT JOIN taches t ON e.id = t.employe_assigne
WHERE e.status = 'Actif'
GROUP BY e.id, e.prenom, e.nom;

CREATE OR REPLACE VIEW vue_chiffre_affaires AS
SELECT 
    YEAR(d.date_creation) as annee,
    MONTH(d.date_creation) as mois,
    COUNT(*) as nombre_dossiers,
    SUM(d.montant_honoraires) as ca_total,
    AVG(d.montant_honoraires) as ca_moyen,
    SUM(CASE WHEN d.status = 'Terminé' THEN d.montant_honoraires ELSE 0 END) as ca_facture
FROM dossiers d
WHERE d.montant_honoraires > 0
GROUP BY YEAR(d.date_creation), MONTH(d.date_creation)
ORDER BY annee DESC, mois DESC;

SET FOREIGN_KEY_CHECKS = 1;
EOF

    # Exécution du script SQL
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" < /tmp/fidaous_schema.sql
    rm /tmp/fidaous_schema.sql
    
    print_success "Schéma de base de données créé"
}

# Création de l'utilisateur administrateur par défaut
create_admin_user() {
    print_status "Création de l'utilisateur administrateur..."
    
    # Mot de passe par défaut (sera changé au premier login)
    ADMIN_PASSWORD_HASH=$(php -r "echo password_hash('admin123', PASSWORD_DEFAULT);")
    
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" -e "
        INSERT INTO employes (matricule, nom, prenom, email, telephone, role_id, date_embauche, mot_de_passe, status) 
        VALUES ('ADM001', 'Administrateur', 'Système', 'admin@fidaous.local', '+212600000000', 1, CURDATE(), '${ADMIN_PASSWORD_HASH}', 'Actif')
        ON DUPLICATE KEY UPDATE email = VALUES(email);"
    
    print_success "Utilisateur admin créé (email: admin@fidaous.local, mot de passe: admin123)"
}

# Configuration des permissions
set_permissions() {
    print_status "Configuration des permissions..."
    
    # Propriétaire des fichiers
    chown -R "${WEB_USER}:${WEB_USER}" "${WEB_DIR}"
    
    # Permissions des dossiers
    find "${WEB_DIR}" -type d -exec chmod 755 {} \;
    
    # Permissions des fichiers
    find "${WEB_DIR}" -type f -exec chmod 644 {} \;
    
    # Dossiers écriture
    chmod 775 "${WEB_DIR}/uploads"
    chmod 775 "${WEB_DIR}/logs"
    
    print_success "Permissions configurées"
}

# Installation de Composer (optionnel)
install_composer() {
    print_status "Installation de Composer..."
    
    if ! command -v composer &> /dev/null; then
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
        print_success "Composer installé"
    else
        print_success "Composer déjà installé"
    fi
}

# Configuration SSL avec Let's Encrypt (optionnel)
setup_ssl() {
    if [[ -n "$DOMAIN_NAME" ]]; then
        print_status "Configuration SSL avec Let's Encrypt..."
        
        # Installation Certbot
        apt-get install -y -qq certbot python3-certbot-nginx
        
        # Obtention du certificat
        certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "admin@${DOMAIN_NAME}" --redirect
        
        # Configuration renouvellement automatique
        echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
        
        print_success "SSL configuré pour $DOMAIN_NAME"
    fi
}

# Configuration du firewall
configure_firewall() {
    print_status "Configuration du firewall..."
    
    # Installation UFW
    apt-get install -y -qq ufw
    
    # Configuration
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    
    print_success "Firewall configuré"
}

# Nettoyage et optimisation
cleanup_and_optimize() {
    print_status "Nettoyage et optimisation..."
    
    # Nettoyage APT
    apt-get autoremove -y -qq
    apt-get autoclean -qq
    
    # Optimisation MySQL
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
        SET GLOBAL innodb_buffer_pool_size = 128M;
        SET GLOBAL max_connections = 100;
        SET GLOBAL query_cache_size = 16M;"
    
    # Redémarrage des services
    systemctl restart mariadb
    systemctl restart php${PHP_VERSION}-fpm
    systemctl restart nginx
    
    print_success "Nettoyage et optimisation terminés"
}

# Affichage du récapitulatif
show_summary() {
    echo -e "\n${GREEN}=== Installation terminée avec succès ===${NC}\n"
    
    echo -e "${BLUE}📋 Récapitulatif de l'installation :${NC}"
    echo "• Application web : ${WEB_DIR}"
    echo "• Base de données : ${DB_NAME}"
    echo "• Utilisateur DB : ${DB_USER}"
    echo "• PHP Version : ${PHP_VERSION}"
    echo "• Serveur web : Nginx"
    
    echo -e "\n${BLUE}🔐 Informations de connexion :${NC}"
    echo "• URL : http://$(hostname -I | awk '{print $1}')${DOMAIN_NAME:+ ou https://$DOMAIN_NAME}"
    echo "• Email admin : admin@fidaous.local"
    echo "• Mot de passe : admin123"
    
    echo -e "\n${YELLOW}⚠️  Prochaines étapes importantes :${NC}"
    echo "1. Changer le mot de passe administrateur"
    echo "2. Configurer les paramètres de messagerie"
    echo "3. Sauvegarder les clés de cryptage"
    echo "4. Tester toutes les fonctionnalités"
    
    echo -e "\n${BLUE}📁 Fichiers importants :${NC}"
    echo "• Configuration : ${WEB_DIR}/config/database.php"
    echo "• Logs Nginx : /var/log/nginx/fidaous-pro-*.log"
    echo "• Logs PHP : /var/log/php${PHP_VERSION}-fpm.log"
    
    echo -e "\n${GREEN}🎉 Fidaous Pro est maintenant opérationnel !${NC}"
}

# Fonction principale
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     FIDAOUS PRO INSTALLER                    ║"
    echo "║              Système de gestion pour cabinet                 ║"
    echo "║                        Version 1.0                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_root
    check_debian_version
    collect_config
    
    print_status "Début de l'installation automatisée..."
    
    update_system
    install_dependencies
    install_mariadb
    install_php
    install_nginx
    create_app_structure
    install_app_files
    create_database_schema
    create_admin_user
    set_permissions
    install_composer
    setup_ssl
    configure_firewall
    cleanup_and_optimize
    
    show_summary
}

# Gestion des options de ligne de commande
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --help, -h     Afficher cette aide"
        echo "  --version, -v  Afficher la version"
        echo ""
        echo "Installation automatisée de Fidaous Pro sur Debian 12"
        echo "Installe et configure : MariaDB, PHP 8.2, Nginx, SSL optionnel"
        exit 0
        ;;
    --version|-v)
        echo "Fidaous Pro Installer v1.0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
