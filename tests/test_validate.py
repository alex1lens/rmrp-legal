import unittest
from parser.validate import validate

def fixture():
    return {"server":"Тверской","articles":[{"id":"test-1","document":"TEST","number":"1","text":"Synthetic test","source":"https://forum.rmrp.ru/","status":"active","sanctions":[]}]}

class ValidationTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate(fixture()),1)
    def test_empty(self):
        d=fixture(); d["articles"]=[]
        with self.assertRaises(ValueError): validate(d)
    def test_duplicate(self):
        d=fixture(); d["articles"]*=2
        with self.assertRaises(ValueError): validate(d)
    def test_repealed(self):
        d=fixture(); d["articles"][0]["status"]="repealed"
        with self.assertRaises(ValueError): validate(d)
    def test_wrong_server(self):
        d=fixture(); d["server"]="other"
        with self.assertRaises(ValueError): validate(d)
    def test_missing_sanctions(self):
        d=fixture(); del d["articles"][0]["sanctions"]
        with self.assertRaises(ValueError): validate(d)
