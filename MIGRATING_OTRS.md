# English Version

The following describes the migration from OTRS to KIX. It's absolutely necessary to fulfill all the requirements and to follow the steps.

## Requirements

* the OTRS system has to be framework version 5.0.x 
* please make sure you have a consistent package stack (corresponding versions)
* the OTRS system uses the same DBMS like KIX (PostgreSQL, MariaDB or MySQL)
* the KIX database must be local
* make sure the following packages are installed in your OTRS before your start the migration
 * FAQ
 * GeneralCatalog
 * ImportExport
 * ITSMCore
 * ITSMConfigurationManagement
 * ITSMIncidentProblemManagement

## Hints for special cases

### Previous OTRS 4 with NotificationEventX
* Check for database table ```overlay_agent```
* If does not exist:
    * Create file ```/tmp/FIX_NotificationEventX.xml``` (Look at plain text if content is not shown)
```
<?xml version="1.0" encoding="utf-8" ?>
<database Name="kix">
    <Table Name="overlay_agent">
        <Column Name="id"      Required="true" Type="INTEGER"  PrimaryKey="true" AutoIncrement="true"/>
        <Column Name="subject" Required="true" Type="VARCHAR" Size="250"/>
        <Column Name="message" Required="true" Type="VARCHAR" Size="65535"/>
        <Column Name="decay"   Required="true" Type="INTEGER"/>
        <Column Name="user_id" Required="true" Type="INTEGER"/>
        <Column Name="popup"   Required="true" Type="INTEGER"/>
    </Table>
</database>
```
    * Execute file to database
    * ```sudo -u www-data <OTRS-Home>/bin/otrs.Console.pl Dev::Tools::Database::XMLExecute /tmp/FIX_NotificationEventX.xml```

### OTRS 5 with KIXTemplateWorkflows (NOT KIX16)
* Dump database for tables
    * `kix_template_workflows`
    * `kix_template_workflows_ap`
    * `kix_template_workflows_ap_pref`
    * `kix_template_workflows_ap_link`
* Deinstall package KIXTemplateWorkflows
* Run migration
* Restore database dump

### Migrating to KIXPro with filled CMDB without OptimizedCMDB
* AFTER MIGRATION run console command `Admin::ITSM::RebuildCMDBStructure`
    * Error logs will occure that tables, indexes and views already exists. These can be ignored. It should be checked that there was no error regarding INSERT- or UPDATE-Statements

## Steps

* stop the daemon in the OTRS system
 * ```sudo -u www-data <OTRS-Home>/bin/otrs.Daemon.pl stop```
* stop cronjobs in the OTRS system
 * ```<OTRS Home>/bin/Cron.sh stop <OTRS user>```
* stop apache
* go to the KIX application directory 
 * ```cd /opt/kix``` 
* execute migration script
 * ```scripts/migrate_otrs2kix.sh```
  * follow the instuctions
  * wait... 
* copy special config from your OTRS Config.pm to KIX Config.pm
 * copy your old SystemID to the SystemID config attribute in the KIX Config.pm 
 * do not change the rest of the existing KIX config! 
* remove old OTRS config from apache
* deactivate mod_perl
 * this is only necessary if you want to work in both systems
* start apache
* re-install the remaining installed packages using the console package manager
 * ```sudo -u <apache user> /opt/kix/bin/kix.Console.pl Admin::Package::Reinstall --force <package name>```
* copy article attachments in the filesystem from old OTRS installation to KIX
 * ```cp -rvp <OTRS-Home>/var/article /opt/kix/var```
* if exists, copy CI images in the filesystem from old OTRS installation to KIX
 * ```cp -rvp <OTRS-Home>/var/ITSMConfigItem /opt/kix/var```
* if exists, copy CI attribute attachments in the filesystem from old OTRS installation to KIX
 * ```cp -rvp <OTRS-Home>/var/attachments /opt/kix/var```
* rebuild Config
* clear caches
* reload apache
* check cronjobs in KIX system
 * copy special cronjobs and adjust and validate configuration
* start cronjobs in KIX system
 * ```/opt/kix/bin/Cron.sh start <apache user>```
* start daemon in KIX system
 * ```sudo -u www-data /opt/kix/bin/kix.Daemon.pl start```

# Deutsche Version

Im Folgenden wird das Vorgehen für die Migration einer OTRS-Instanz auf KIX beschrieben. Es ist zwingend notwendig, die Voraussetzungen zu erfüllen und die Schritte einzuhalten. 

## Voraussetzungen

* das OTRS-System ist auf dem Framework-Stand 5.0.x 
* bitte sicherstellen, dass ein konsistenter Paketstack vorliegt (zusammenpassende Paketversionen)
* das OTRS-System verwendet das gleiche DBMS wie KIX (PostgreSQL, MariaDB oder MySQL) 
* die KIX-Datenbank muss lokal installiert sein
* stellen Sie sicher, dass die folgenden Pakete in Ihrem OTRS installiert sind, bevor Sie mit der Migration beginnen
 * FAQ
 * GeneralCatalog
 * ImportExport
 * ITSMCore
 * ITSMConfigurationManagement
 * ITSMIncidentProblemManagement

## Hinweise zu Sonderfällen

### Ursprüngliches OTRS 4 mit NotificationEventX
* Prüfen ob Tabelle ```overlay_agent``` vorhanden ist
* Wenn nicht:
    * Datei ```/tmp/FIX_NotificationEventX.xml``` anlegen (In Klartext schauen, wenn Inhalt nicht angezeigt wird)
```
<?xml version="1.0" encoding="utf-8" ?>
<database Name="kix">
    <Table Name="overlay_agent">
        <Column Name="id"      Required="true" Type="INTEGER"  PrimaryKey="true" AutoIncrement="true"/>
        <Column Name="subject" Required="true" Type="VARCHAR" Size="250"/>
        <Column Name="message" Required="true" Type="VARCHAR" Size="65535"/>
        <Column Name="decay"   Required="true" Type="INTEGER"/>
        <Column Name="user_id" Required="true" Type="INTEGER"/>
        <Column Name="popup"   Required="true" Type="INTEGER"/>
    </Table>
</database>
```
    * Datei in Datenbank einlesen
    * ```sudo -u www-data <OTRS-Home>/bin/otrs.Console.pl Dev::Tools::Database::XMLExecute /tmp/FIX_NotificationEventX.xml```

### OTRS 5 mit KIXTemplateWorkflows (Kein KIX16)
* Datenbank-Dump von Tabellen erstellen
    * `kix_template_workflows`
    * `kix_template_workflows_ap`
    * `kix_template_workflows_ap_pref`
    * `kix_template_workflows_ap_link`
* Paket KIXTemplateWorkflows deinstallieren
* Migration durchführen
* Datenbank-Dump einspielen

### Migration zu KIXPro mit gefüllter CMDB ohne OptimizedCMDB
* NACH DER MIGRATION Konsolenbefehl `Admin::ITSM::RebuildCMDBStructure` ausführen
    * Es wird Fehlermeldungen geben, dass Tabellen, Indizes und Views bereits existieren. Diese können ignoriert werden. Es sollte geprüft werden ob Fehler zu INSERT- oder UPDATE-Anweisungen aufgetreten sind

## Vorgehen

* Daemon in OTRS-Instanz stoppen
 * ```sudo -u www-data <OTRS-Home>/bin/otrs.Daemon.pl stop```
* Cronjobs in OTRS-Instanz stoppen
 * ```<OTRS-Home>/bin/Cron.sh stop <OTRS-Nutzer>```
* Apache stoppen
* ins KIX-Verzeichnis wechseln
 * ```cd /opt/kix``` 
* Migrationsscript ausführen
  * ```scripts/migrate_otrs2kix.sh```
   * Instruktionen folgen
   * warten... 
* spezielle Konfigurationen aus der alten Config.pm in die neue Config.pm von KIX übertragen
 * die alte SystemID in das SystemID-Config-Attribut der KIX Config.pm kopieren 
 * nicht die restliche bestehende KIX-Konfiguration überschreiben!  
* alte OTRS config aus Apache entfernen
* mod_perl deaktivieren
 * nur notwendig, falls man parallel in OTRS und KIX arbeiten will
* Apache starten 
* abschließend die übrigen installierten Pakete im Paket-Manager auf der Console re-installieren
 * ```sudo -u <apache user> /opt/kix/bin/kix.Console.pl Admin::Package::Reinstall --force <package name>```
* die Artikel-Attachments im Dateisystem von der alten OTRS-Installation nach KIX kopieren
 * ```cp -rvp <OTRS-Home>/var/article /opt/kix/var```
* falls vorhanden, die CI-Bilder im Dateisystem von der alten OTRS-Installation nach KIX kopieren
 * ```cp -rvp <OTRS-Home>/var/ITSMConfigItem /opt/kix/var```
* falls vorhanden, die CI-Attribute-Attachments im Dateisystem von der alten OTRS-Installation nach KIX kopieren
 * ```cp -rvp <OTRS-Home>/var/attachments /opt/kix/var```
* Config rebuild
* Caches löschen
* Apache reload
* Cronjobs in KIX-Instanz prüfen
 * spezielle Cronjobs übertragen und Konfiguration prüfen und ggf. anpassen
* Cronjobs in KIX-Instanz starten
 * ```/opt/kix/bin/Cron.sh start <Apache-Nutzer>```
* Daemon in KIX-Instanz starten
 * ```sudo -u www-data /opt/kix/bin/kix.Daemon.pl start```

