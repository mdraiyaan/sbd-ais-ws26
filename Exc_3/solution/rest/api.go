package rest

import (
	"encoding/json"
	"net/http"
	"ordersystem/model"
	"ordersystem/repository"

	"github.com/go-chi/render"
)

// GetMenu godoc
// @tags Menu
// @Description Returns the menu of all drinks
// @Produce json
// @Success 200 {array} model.Drink
// @Router /api/menu [get]
func GetMenu(db *repository.DatabaseHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		render.Status(r, http.StatusOK)
		render.JSON(w, r, db.GetDrinks())
	}
}

// GetOrders godoc
// @tags Order
// @Description Returns all orders
// @Produce json
// @Success 200 {array} model.Order
// @Router /api/order/all [get]
func GetOrders(db *repository.DatabaseHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		render.Status(r, http.StatusOK)
		render.JSON(w, r, db.GetOrders())
	}
}

// GetOrdersTotal godoc
// @tags Order
// @Description Returns order totals per drink id
// @Produce json
// @Success 200 {object} map[string]uint64
// @Router /api/order/totalled [get]
func GetOrdersTotal(db *repository.DatabaseHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		render.Status(r, http.StatusOK)
		render.JSON(w, r, db.GetTotalledOrders())
	}
}

// PostOrder godoc
// @tags Order
// @Description Adds an order to the db
// @Accept json
// @Param b body model.Order true "Order"
// @Produce json
// @Success 200
// @Failure 400
// @Router /api/order [post]
func PostOrder(db *repository.DatabaseHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var o model.Order
		err := json.NewDecoder(r.Body).Decode(&o)
		if err != nil {
			render.Status(r, http.StatusBadRequest)
			render.JSON(w, r, "bad request")
			return
		}

		db.AddOrder(&o)
		render.Status(r, http.StatusOK)
		render.JSON(w, r, "ok")
	}
}
