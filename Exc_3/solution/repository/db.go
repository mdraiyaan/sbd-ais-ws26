package repository

import (
	"ordersystem/model"
	"time"
)

type DatabaseHandler struct {
	drinks []model.Drink
	orders []model.Order
}

func NewDatabaseHandler() *DatabaseHandler {
	drinks := []model.Drink{
		{ID: 1, Name: "Beer", Price: 3.80, Description: "Beer"},
		{ID: 2, Name: "Wine", Price: 4.20, Description: "Red wine"},
		{ID: 3, Name: "Cola", Price: 2.50, Description: "Coke"},
		{ID: 4, Name: "Water", Price: 1.50, Description: "Water"},
	}

	orders := []model.Order{
		{DrinkID: 1, Amount: 2, CreatedAt: time.Now()},
		{DrinkID: 3, Amount: 1, CreatedAt: time.Now()},
	}

	return &DatabaseHandler{
		drinks: drinks,
		orders: orders,
	}
}

func (db *DatabaseHandler) GetDrinks() []model.Drink {
	return db.drinks
}

func (db *DatabaseHandler) GetOrders() []model.Order {
	return db.orders
}

func (db *DatabaseHandler) GetTotalledOrders() map[uint64]uint64 {
	totals := make(map[uint64]uint64)
	for _, o := range db.orders {
		totals[o.DrinkID] += o.Amount
	}
	return totals
}

func (db *DatabaseHandler) AddOrder(order *model.Order) {
	if order.CreatedAt.IsZero() {
		order.CreatedAt = time.Now()
	}
	db.orders = append(db.orders, *order)
}
