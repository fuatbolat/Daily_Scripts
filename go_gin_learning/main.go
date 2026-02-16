package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	// Gin router'ı oluştur
	// gin.Default() --> Logger ve Recovery middleware'leri ile birlikte gelir
	router := gin.Default()

	// GET endpoint'i tanımla
	// "/" path'ine gelen GET isteklerini yakalar
	router.GET("/", func(c *gin.Context) {
		// JSON yanıt döndür
		// c.JSON(HTTP_STATUS_CODE, data)
		c.JSON(http.StatusOK, gin.H{
			"message": "Merhaba Dünya! 🚀",
			"status":  "success",
		})
	})

	// Başka bir endpoint ekleyelim
	router.GET("/hello/:name", func(c *gin.Context) {
		// URL'den parametre al
		// Örnek: /hello/Fuat --> name = "Fuat"
		name := c.Param("name")

		c.JSON(http.StatusOK, gin.H{
			"message": "Merhaba " + name + "!",
			"name":    name,
		})
	})

	// Server'ı başlat (port 8080)
	// Tarayıcıdan http://localhost:8080 adresine gidebilirsin
	router.Run(":8080")
}
