# Systems

Sistemas de servidor creados a partir de `Services` cuando la logica
se vuelve compartida por varios servicios y ya tiene un comportamiento
estable y probado.

Regla: si un archivo solo lo usa un servicio, vive en `Services`.
No se crea nada aqui durante el bootstrap.
