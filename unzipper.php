<?php
/**
 * The Unzipper extracts .zip or .rar archives and .gz files on webservers.
 * It's handy if you do not have shell access. E.g. if you want to upload a lot
 * of files (php framework or image collection) as an archive to save time.
 * As of version 0.1.0 it also supports creating archives.
 *
 * @author  Andreas Tasch, at[tec], attec.at
 * @license GNU GPL v3
 * @package attec.toolbox
 * @version 0.1.1
 */
define('VERSION', '0.1.1');

// ---------------------------------------------------------------------------
// SECURITY: Password protection.
// Change the password by editing PLAIN password below and regenerating the
// hash, or simply replace UNZIPPER_PASSWORD_HASH with a new hash generated
// with: php -r "echo password_hash('yourpassword', PASSWORD_DEFAULT);"
// ---------------------------------------------------------------------------
define('UNZIPPER_PASSWORD_HASH', '$2b$10$s4LhsX0akRP7gkUvtn535ew.g9bjId2AhfHa0TqjRtQbxr9DN9uvq');

session_start();

// Handle login.
if (isset($_POST['unzipper_login'])) {
  $inputPassword = isset($_POST['password']) ? $_POST['password'] : '';
  if (password_verify($inputPassword, UNZIPPER_PASSWORD_HASH)) {
    // Regenerate session ID on successful login to prevent session fixation.
    session_regenerate_id(true);
    $_SESSION['unzipper_auth'] = true;
  }
  else {
    $loginError = 'Contraseña incorrecta.';
  }
}

// Handle logout.
if (isset($_GET['logout'])) {
  $_SESSION = array();
  session_destroy();
  header('Location: ' . strtok($_SERVER['REQUEST_URI'], '?'));
  exit;
}

// Block everything below this point until authenticated.
if (empty($_SESSION['unzipper_auth'])) {
  ?>
  <!DOCTYPE html>
  <html>
  <head>
    <title>File Unzipper + Zipper - Login</title>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <style>
      body { font-family: Arial, sans-serif; max-width: 320px; margin: 80px auto; }
      .form-field { border: 1px solid #AAA; padding: 8px; width: 100%; box-sizing: border-box; margin-top: 10px; }
      .submit { background-color: #378de5; border: 0; color: #fff; font-size: 15px; padding: 10px 24px; margin-top: 15px; cursor: pointer; }
      .submit:hover { background-color: #2c6db2; }
      .error { color: #c00; font-size: 90%; }
    </style>
  </head>
  <body>
    <h1>Acceso protegido</h1>
    <?php if (!empty($loginError)) { echo '<p class="error">' . htmlspecialchars($loginError) . '</p>'; } ?>
    <form action="" method="POST">
      <label for="password">Contraseña:</label>
      <input type="password" name="password" class="form-field" autofocus />
      <input type="submit" name="unzipper_login" class="submit" value="Entrar" />
    </form>
  </body>
  </html>
  <?php
  exit;
}

$timestart = microtime(TRUE);
$GLOBALS['status'] = array();

$unzipper = new Unzipper;
if (isset($_POST['dounzip'])) {
  // Check if an archive was selected for unzipping.
  $archive = isset($_POST['zipfile']) ? strip_tags($_POST['zipfile']) : '';
  $destination = isset($_POST['extpath']) ? strip_tags($_POST['extpath']) : '';
  $unzipper->prepareExtraction($archive, $destination);
}

if (isset($_POST['dozip'])) {
  $zippath = !empty($_POST['zippath']) ? strip_tags($_POST['zippath']) : '.';
  // Resulting zipfile e.g. zipper--2016-07-23--11-55.zip.
  $zipfile = 'zipper-' . date("Y-m-d--H-i") . '.zip';
  Zipper::zipDir($zippath, $zipfile);
}

$timeend = microtime(TRUE);
$time = round($timeend - $timestart, 4);

/**
 * SECURITY: Resolve a user-supplied relative path against a base directory
 * and make sure the result stays inside that base directory (prevents
 * path/directory traversal via "../", absolute paths, symlinks, etc.).
 *
 * @param string $baseDir
 *   The directory that must contain the result (e.g. the script's own dir).
 * @param string $relativePath
 *   The user-supplied relative path. May be empty.
 * @param bool $mustExist
 *   If TRUE, the resolved path must already exist (used for files/paths that
 *   are read, e.g. the folder to be zipped). If FALSE, the target itself is
 *   allowed not to exist yet (used for extraction destinations, which may
 *   still need to be created) as long as its parent exists and is inside
 *   the base directory.
 *
 * @return string|false
 *   The safe, resolved absolute path, or FALSE if the path is invalid or
 *   escapes the base directory.
 */
function unzipper_safe_path($baseDir, $relativePath, $mustExist = TRUE) {
  $baseReal = realpath($baseDir);
  if ($baseReal === FALSE) {
    return FALSE;
  }

  // Strip null bytes and reject absolute paths outright.
  $relativePath = str_replace("\0", '', $relativePath);
  if ($relativePath !== '' && ($relativePath[0] === '/' || $relativePath[0] === '\\' || preg_match('#^[a-zA-Z]:[\\\\/]#', $relativePath))) {
    return FALSE;
  }

  $candidate = $relativePath === '' ? $baseReal : $baseReal . DIRECTORY_SEPARATOR . $relativePath;

  if ($mustExist) {
    $real = realpath($candidate);
    if ($real === FALSE) {
      return FALSE;
    }
  }
  else {
    // Target may not exist yet; resolve its parent instead and re-attach
    // the final path segment.
    $parent = realpath(dirname($candidate));
    if ($parent === FALSE) {
      return FALSE;
    }
    $real = $parent . DIRECTORY_SEPARATOR . basename($candidate);
  }

  // Ensure the resolved path is the base dir itself or genuinely inside it.
  if ($real !== $baseReal && strpos($real . DIRECTORY_SEPARATOR, $baseReal . DIRECTORY_SEPARATOR) !== 0) {
    return FALSE;
  }

  return $real;
}

/**
 * Class Unzipper
 */
class Unzipper {
  public $localdir = '.';
  public $zipfiles = array();

  public function __construct() {
    // Read directory and pick .zip, .rar and .gz files.
    if ($dh = opendir($this->localdir)) {
      while (($file = readdir($dh)) !== FALSE) {
        if (pathinfo($file, PATHINFO_EXTENSION) === 'zip'
          || pathinfo($file, PATHINFO_EXTENSION) === 'gz'
          || pathinfo($file, PATHINFO_EXTENSION) === 'rar'
        ) {
          $this->zipfiles[] = $file;
        }
      }
      closedir($dh);

      if (!empty($this->zipfiles)) {
        $GLOBALS['status'] = array('info' => '.zip or .gz or .rar files found, ready for extraction');
      }
      else {
        $GLOBALS['status'] = array('info' => 'No .zip or .gz or rar files found. So only zipping functionality available.');
      }
    }
  }

  /**
   * Prepare and check zipfile for extraction.
   *
   * @param string $archive
   *   The archive name including file extension. E.g. my_archive.zip.
   * @param string $destination
   *   The relative destination path where to extract files.
   */
  public function prepareExtraction($archive, $destination = '') {
    // SECURITY: Validate the destination stays inside localdir before doing
    // anything with it (including mkdir).
    $safeDestination = unzipper_safe_path($this->localdir, $destination, FALSE);
    if ($safeDestination === FALSE) {
      $GLOBALS['status'] = array('error' => 'Error: Ruta de destino no válida o fuera del directorio permitido.');
      return;
    }

    if (!is_dir($safeDestination)) {
      mkdir($safeDestination, 0755, TRUE);
    }

    // Only local existing archives are allowed to be extracted.
    if (in_array($archive, $this->zipfiles, TRUE)) {
      // Re-validate the archive path itself (defense in depth), even though
      // it comes from the whitelist built by scanning localdir.
      $safeArchive = unzipper_safe_path($this->localdir, $archive, TRUE);
      if ($safeArchive === FALSE) {
        $GLOBALS['status'] = array('error' => 'Error: Archivo de origen no válido.');
        return;
      }
      self::extract($safeArchive, $safeDestination);
    }
    else {
      $GLOBALS['status'] = array('error' => 'Error: Archivo no permitido.');
    }
  }

  /**
   * Checks file extension and calls suitable extractor functions.
   *
   * @param string $archive
   *   The archive name including file extension. E.g. my_archive.zip.
   * @param string $destination
   *   The relative destination path where to extract files.
   */
  public static function extract($archive, $destination) {
    $ext = pathinfo($archive, PATHINFO_EXTENSION);
    switch ($ext) {
      case 'zip':
        self::extractZipArchive($archive, $destination);
        break;
      case 'gz':
        self::extractGzipFile($archive, $destination);
        break;
      case 'rar':
        self::extractRarArchive($archive, $destination);
        break;
    }

  }

  /**
   * Decompress/extract a zip archive using ZipArchive.
   *
   * @param $archive
   * @param $destination
   */
  public static function extractZipArchive($archive, $destination) {
    // Check if webserver supports unzipping.
    if (!class_exists('ZipArchive')) {
      $GLOBALS['status'] = array('error' => 'Error: Your PHP version does not support unzip functionality.');
      return;
    }

    $zip = new ZipArchive;

    // Check if archive is readable.
    if ($zip->open($archive) === TRUE) {
      // Check if destination is writable
      if (is_writeable($destination . '/')) {
        // SECURITY: Guard against Zip Slip by checking every entry name
        // resolves inside $destination before extracting. Modern PHP
        // (>= 8.0) already sanitizes this internally, but we double-check
        // for older/hosted PHP versions.
        $safe = TRUE;
        for ($i = 0; $i < $zip->numFiles; $i++) {
          $entryName = $zip->getNameIndex($i);
          if ($entryName === FALSE) {
            continue;
          }
          $entryTarget = realpath(dirname($destination . '/' . $entryName));
          $destReal = realpath($destination);
          if ($entryTarget === FALSE || $destReal === FALSE || strpos($entryTarget . DIRECTORY_SEPARATOR, $destReal . DIRECTORY_SEPARATOR) !== 0) {
            // Entry would land outside the destination folder.
            if (strpos($entryName, '..') !== FALSE || $entryName[0] === '/') {
              $safe = FALSE;
              break;
            }
          }
        }

        if (!$safe) {
          $zip->close();
          $GLOBALS['status'] = array('error' => 'Error: El archivo .zip contiene rutas no seguras (posible Zip Slip) y no se ha extraído.');
          return;
        }

        $zip->extractTo($destination);
        $zip->close();
        $GLOBALS['status'] = array('success' => 'Files unzipped successfully');
      }
      else {
        $GLOBALS['status'] = array('error' => 'Error: Directory not writeable by webserver.');
      }
    }
    else {
      $GLOBALS['status'] = array('error' => 'Error: Cannot read .zip archive.');
    }
  }

  /**
   * Decompress a .gz File.
   *
   * @param string $archive
   *   The archive name including file extension. E.g. my_archive.zip.
   * @param string $destination
   *   The relative destination path where to extract files.
   */
  public static function extractGzipFile($archive, $destination) {
    // Check if zlib is enabled
    if (!function_exists('gzopen')) {
      $GLOBALS['status'] = array('error' => 'Error: Your PHP has no zlib support enabled.');
      return;
    }

    $filename = pathinfo($archive, PATHINFO_FILENAME);
    $gzipped = gzopen($archive, "rb");
    $file = fopen($destination . '/' . $filename, "w");

    while ($string = gzread($gzipped, 4096)) {
      fwrite($file, $string, strlen($string));
    }
    gzclose($gzipped);
    fclose($file);

    // Check if file was extracted.
    if (file_exists($destination . '/' . $filename)) {
      $GLOBALS['status'] = array('success' => 'File unzipped successfully.');

      // If we had a tar.gz file, let's extract that tar file.
      if (pathinfo($destination . '/' . $filename, PATHINFO_EXTENSION) == 'tar') {
        $phar = new PharData($destination . '/' . $filename);
        if ($phar->extractTo($destination)) {
          $GLOBALS['status'] = array('success' => 'Extracted tar.gz archive successfully.');
          // Delete .tar.
          unlink($destination . '/' . $filename);
        }
      }
    }
    else {
      $GLOBALS['status'] = array('error' => 'Error unzipping file.');
    }

  }

  /**
   * Decompress/extract a Rar archive using RarArchive.
   *
   * @param string $archive
   *   The archive name including file extension. E.g. my_archive.zip.
   * @param string $destination
   *   The relative destination path where to extract files.
   */
  public static function extractRarArchive($archive, $destination) {
    // Check if webserver supports unzipping.
    if (!class_exists('RarArchive')) {
      $GLOBALS['status'] = array('error' => 'Error: Your PHP version does not support .rar archive functionality. <a class="info" href="http://php.net/manual/en/rar.installation.php" target="_blank">How to install RarArchive</a>');
      return;
    }
    // Check if archive is readable.
    if ($rar = RarArchive::open($archive)) {
      // Check if destination is writable
      if (is_writeable($destination . '/')) {
        $entries = $rar->getEntries();
        foreach ($entries as $entry) {
          // SECURITY: Skip entries whose name tries to escape the
          // destination folder (Zip Slip equivalent for .rar).
          $entryName = $entry->getName();
          if (strpos($entryName, '..') !== FALSE || (isset($entryName[0]) && $entryName[0] === '/')) {
            continue;
          }
          $entry->extract($destination);
        }
        $rar->close();
        $GLOBALS['status'] = array('success' => 'Files extracted successfully.');
      }
      else {
        $GLOBALS['status'] = array('error' => 'Error: Directory not writeable by webserver.');
      }
    }
    else {
      $GLOBALS['status'] = array('error' => 'Error: Cannot read .rar archive.');
    }
  }

}

/**
 * Class Zipper
 *
 * Copied and slightly modified from http://at2.php.net/manual/en/class.ziparchive.php#110719
 * @author umbalaconmeogia
 */
class Zipper {
  /**
   * Add files and sub-directories in a folder to zip file.
   *
   * @param string $folder
   *   Path to folder that should be zipped.
   *
   * @param ZipArchive $zipFile
   *   Zipfile where files end up.
   *
   * @param int $exclusiveLength
   *   Number of text to be exclusived from the file path.
   */
  private static function folderToZip($folder, &$zipFile, $exclusiveLength) {
    $handle = opendir($folder);

    while (FALSE !== $f = readdir($handle)) {
      // Check for local/parent path or zipping file itself and skip.
      if ($f != '.' && $f != '..' && $f != basename(__FILE__)) {
        $filePath = "$folder/$f";
        // Remove prefix from file path before add to zip.
        $localPath = substr($filePath, $exclusiveLength);

        if (is_file($filePath)) {
          $zipFile->addFile($filePath, $localPath);
        }
        elseif (is_dir($filePath)) {
          // Add sub-directory.
          $zipFile->addEmptyDir($localPath);
          self::folderToZip($filePath, $zipFile, $exclusiveLength);
        }
      }
    }
    closedir($handle);
  }

  /**
   * Zip a folder (including itself).
   *
   * Usage:
   *   Zipper::zipDir('path/to/sourceDir', 'path/to/out.zip');
   *
   * @param string $sourcePath
   *   Relative path of directory to be zipped.
   *
   * @param string $outZipPath
   *   Relative path of the resulting output zip file.
   */
  public static function zipDir($sourcePath, $outZipPath) {
    // SECURITY: Validate sourcePath stays inside the current directory
    // before reading from it, to prevent zipping/exfiltrating arbitrary
    // files elsewhere on the server (e.g. "../../etc").
    $safeSource = unzipper_safe_path('.', $sourcePath, TRUE);
    if ($safeSource === FALSE || !is_dir($safeSource)) {
      $GLOBALS['status'] = array('error' => 'Error: Ruta a comprimir no válida o fuera del directorio permitido.');
      return;
    }

    $pathInfo = pathinfo($safeSource);
    $parentPath = $pathInfo['dirname'];
    $dirName = $pathInfo['basename'];

    $z = new ZipArchive();
    $z->open($outZipPath, ZipArchive::CREATE);
    $z->addEmptyDir($dirName);
    if ($safeSource == $dirName) {
      self::folderToZip($safeSource, $z, 0);
    }
    else {
      self::folderToZip($safeSource, $z, strlen("$parentPath/"));
    }
    $z->close();

    $GLOBALS['status'] = array('success' => 'Successfully created archive ' . $outZipPath);
  }
}
?>

<!DOCTYPE html>
<html>
<head>
  <title>File Unzipper + Zipper</title>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <style type="text/css">
    <!--
    body {
      font-family: Arial, sans-serif;
      line-height: 150%;
    }

    label {
      display: block;
      margin-top: 20px;
    }

    fieldset {
      border: 0;
      background-color: #EEE;
      margin: 10px 0 10px 0;
    }

    .select {
      padding: 5px;
      font-size: 110%;
    }

    .status {
      margin: 0;
      margin-bottom: 20px;
      padding: 10px;
      font-size: 80%;
      background: #EEE;
      border: 1px dotted #DDD;
    }

    .status--ERROR {
      background-color: red;
      color: white;
      font-size: 120%;
    }

    .status--SUCCESS {
      background-color: green;
      font-weight: bold;
      color: white;
      font-size: 120%
    }

    .small {
      font-size: 0.7rem;
      font-weight: normal;
    }

    .version {
      font-size: 80%;
    }

    .form-field {
      border: 1px solid #AAA;
      padding: 8px;
      width: 280px;
    }

    .info {
      margin-top: 0;
      font-size: 80%;
      color: #777;
    }

    .submit {
      background-color: #378de5;
      border: 0;
      color: #ffffff;
      font-size: 15px;
      padding: 10px 24px;
      margin: 20px 0 20px 0;
      text-decoration: none;
    }

    .submit:hover {
      background-color: #2c6db2;
      cursor: pointer;
    }

    .logout {
      float: right;
      font-size: 80%;
    }
    -->
  </style>
</head>
<body>
<p class="logout"><a href="?logout=1">Cerrar sesión</a></p>
<p class="status status--<?php echo strtoupper(key($GLOBALS['status'])); ?>">
  Status: <?php echo reset($GLOBALS['status']); ?><br/>
  <span class="small">Processing Time: <?php echo $time; ?> seconds</span>
</p>
<form action="" method="POST">
  <fieldset>
    <h1>Archive Unzipper</h1>
    <label for="zipfile">Select .zip or .rar archive or .gz file you want to extract:</label>
    <select name="zipfile" size="1" class="select">
      <?php foreach ($unzipper->zipfiles as $zip) {
        echo "<option>$zip</option>";
      }
      ?>
    </select>
    <label for="extpath">Extraction path (optional):</label>
    <input type="text" name="extpath" class="form-field" />
    <p class="info">Enter extraction path without leading or trailing slashes (e.g. "mypath"). If left empty current directory will be used.</p>
    <input type="submit" name="dounzip" class="submit" value="Unzip Archive"/>
  </fieldset>

  <fieldset>
    <h1>Archive Zipper</h1>
    <label for="zippath">Path that should be zipped (optional):</label>
    <input type="text" name="zippath" class="form-field" />
    <p class="info">Enter path to be zipped without leading or trailing slashes (e.g. "zippath"). If left empty current directory will be used.</p>
    <input type="submit" name="dozip" class="submit" value="Zip Archive"/>
  </fieldset>
</form>
<p class="version">Unzipper version: <?php echo VERSION; ?></p>
</body>
</html>
