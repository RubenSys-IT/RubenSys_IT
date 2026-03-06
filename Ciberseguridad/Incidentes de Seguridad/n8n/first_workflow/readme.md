&nbsp;Sistema de Detección de Intrusiones en Honey‑Trap con n8n

Automatización de alertas, análisis de riesgo y registro forense



Descripción del incidente detectado

Este workflow implementa un sistema de detección temprana de intrusiones basado en una honey‑trap: un endpoint expuesto que no debería recibir tráfico legítimo.

Cualquier acceso a este endpoint se considera sospechoso. El sistema analiza automáticamente:

• La IP de origen

• El User‑Agent utilizado

• El nivel de riesgo asociado

• El momento exacto del evento

El objetivo es identificar accesos realizados con herramientas ofensivas como sqlmap, nmap u otros agentes automatizados utilizados en reconocimiento y explotación.



Lógica de detección

El flujo sigue una lógica simple pero realista, inspirada en procedimientos de un SOC:

1\. Recepción del evento

Un Webhook recibe cualquier petición POST enviada al endpoint .

2\. Análisis del User‑Agent

En un Code Node se evalúa el encabezado :

• Si contiene patrones asociados a herramientas de hacking → CRÍTICO

• Si parece un navegador o dispositivo común → BAJO

• Se registra también la IP y el timestamp para trazabilidad

3\. Decisión

Un nodo IF determina si el incidente es crítico, diferenciando entre:

• Curiosos o escaneos triviales

• Ataques automatizados reales

4\. Respuesta automatizada

Si el incidente es crítico, el sistema:

• Envía alerta inmediata a Telegram

• Escala por email al administrador

• Registra el incidente en PostgreSQL

Si no es crítico, solo se registra en la base de datos, evitando ruido innecesario.



Justificación de los criterios utilizados

El análisis del  es un método eficaz para detectar actividad automatizada porque muchas herramientas ofensivas incluyen identificadores claros en este encabezado. Esto permite distinguir entre:

• Tráfico legítimo (navegadores, móviles)

• Tráfico malicioso (sqlmap, nmap, scripts automatizados)

La clasificación en niveles BAJO y CRÍTICO replica el funcionamiento de un SOC real, donde no todas las alertas requieren la misma respuesta.

El uso combinado de Telegram y MailHog simula un sistema profesional de notificación:

• Telegram → alerta inmediata

• Email → escalado formal



El registro en PostgreSQL garantiza evidencia forense y permite auditorías posteriores.



Cómo probar el workflow

Prueba de caso NO crítico (BAJO)

Simula un acceso normal desde un navegador móvil:

curl -X POST http://localhost:5678/webhook-test/honey-trap-access \\

&nbsp; -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17\_0 like Mac OS X)" \\

&nbsp; -d '{"nota": "esta es una peticion normal"}'



Resultado esperado:

• No se envía alerta

• No se envía email

• Se registra en DB como BAJO



Prueba de caso crítico (CRÍTICO)

Simula un ataque real usando sqlmap:

curl -i -X POST http://localhost:5678/webhook-test/honey-trap-access \\

&nbsp; -H "User-Agent: sqlmap/1.4.11 (http://sqlmap.org)" \\

&nbsp; -d '{"test": "probando trap"}'



Resultado esperado:

• Alerta en Telegram

• Email en MailHog

• Registro en DB como CRÍTICO



Verificar registros en la base de datos

docker exec -it postgres psql -U n8n\_user -d n8n\_db \\

&nbsp; -c "SELECT \* FROM incidentes;"



Deberías ver entradas con IP, agente, nivel y fecha.



Futuras mejoras:

\- Añadir un contador de intentos por IP

\- Implementar un bloqueo simulado mediante lista negra

\- Crear un dashboard en Grafana con métricas



