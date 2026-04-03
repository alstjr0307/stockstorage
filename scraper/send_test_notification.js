const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const token = 'e9yAYYZ3TkL1nmVUIUKGC6:APA91bGs_a7rY9ZXsdjaHsyqJg0MqxQGtzZklqiU6lwm7c3rP3336Wd7VySFrl4PZ9eEpZ3vSEd3oFUrZtbtmBBJaxH3e_sFZXltZHctEfZxPtWW1PhXAYw';

const message = {
  notification: {
    title: '테스트 알림',
    body: '알림이 정상적으로 작동합니다!',
  },
  token,
};

admin.messaging().send(message)
  .then(response => {
    console.log('알림 전송 성공:', response);
  })
  .catch(error => {
    console.error('알림 전송 실패:', error.message);
  });
