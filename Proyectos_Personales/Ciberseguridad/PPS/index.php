<?php
$servername = "db";
$username = "root";
$password = getenv("ROOT_PASSWORD");

try {
    $conn = new PDO("mysql:host=$servername", $username, $password);
    echo "Conexión exitosa - Rodríguez Garrido Rubén";
} catch (PDOException $e) {
    echo "Error de conexión: " . $e->getMessage();
}
?>
