function arrayHasElementWithSameTimestampAndProperty(array,t,propname,id) {
    for (var j=0; j < array.length; j++) {
        var element = array[j];
        // Check if IDs are present and different - if so, not a duplicate
        if (id && element.id && id !== element.id) {
            continue;
        }
        if (element.timestamp === t && element[propname] !== undefined) return true;
        if ( element[propname] !== undefined ) {
            var eDate = new Date(element.timestamp);
            var tDate = new Date(t);
            var tMin = new Date(tDate.getTime() - 2000);
            var tMax = new Date(tDate.getTime() + 2000);
            //console.error(tDate, tMin, tMax);
            if (eDate > tMin && eDate < tMax) return true;
        }
    }
    return false;
}

function findMealInputs (inputs) {
    var pumpHistory = inputs.history;
    var carbHistory = inputs.carbs;
    var profile_data = inputs.profile;
    var mealInputs = [];
    var bolusWizardInputs = [];
    var duplicates = 0;

    for (var i=0; i < carbHistory.length; i++) {
        var current = carbHistory[i];
        if (current.carbs && current.created_at) {
            var temp = {};
            temp.timestamp = current.created_at;
            temp.carbs = current.carbs;
            temp.nsCarbs = current.carbs;
            temp.id = current.id;
        if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.created_at,"carbs",current.id)) {
                mealInputs.push(temp);
            } else {
                duplicates += 1;
            }
        }
    }

    for (i=0; i < pumpHistory.length; i++) {
        current = pumpHistory[i];
        if (current._type === "Bolus" && current.timestamp) {
            //console.log(pumpHistory[i]);
            temp = {};
            temp.timestamp = current.timestamp;
            temp.bolus = current.amount;
            temp.id = current.id;

            if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"bolus",current.id)) {
                mealInputs.push(temp);
            } else {
                duplicates += 1;
            }
        } else if (current._type === "BolusWizard" && current.timestamp) {
            // Delay process the BolusWizard entries to make sure we've seen all possible that correspond to the bolus wizard.
            // More specifically, we need to make sure we process the corresponding bolus entry first.
            bolusWizardInputs.push(current);

        } else if ((current._type === "Meal Bolus" || current._type === "Correction Bolus" || current._type === "Snack Bolus" || current._type === "Bolus Wizard" || current._type === "Carb Correction") && current.created_at) {
            //imports carbs entered through Nightscout Care Portal
            //"Bolus Wizard" refers to the Nightscout Bolus Wizard, not the Medtronic Bolus Wizard
            temp = {};
            temp.timestamp = current.created_at;
            temp.carbs = current.carbs;
            temp.nsCarbs = current.carbs;
            temp.id = current.id;
            // don't enter the treatment if there's another treatment with the same exact timestamp
            // to prevent duped carb entries from multiple sources
            if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.created_at,"carbs",current.id)) {
                mealInputs.push(temp);
            } else {
                duplicates += 1;
            }
        } else if (current.enteredBy === "xdrip") {
            temp = {};
            temp.timestamp = current.created_at;
            temp.carbs = current.carbs;
            temp.nsCarbs = current.carbs;
            temp.bolus = current.insulin;
            temp.id = current.id;
            if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"carbs",current.id)) {
                mealInputs.push(temp);
            } else {
                duplicates += 1;
            }
        } else if (current.carbs > 0) {
            temp = {};
            temp.carbs = current.carbs;
            temp.nsCarbs = current.carbs;
            temp.timestamp = current.created_at;
            temp.bolus = current.insulin;
            temp.id = current.id;
            if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"carbs",current.id)) {
                mealInputs.push(temp);
            } else {
                duplicates += 1;
            }
        } else if (current._type === "JournalEntryMealMarker" && current.carb_input > 0 && current.timestamp) {
            temp = {};
            temp.timestamp = current.timestamp;
            temp.carbs = current.carb_input;
            temp.journalCarbs = current.carb_input;
            temp.id = current.id;
            if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"carbs",current.id)) {
                    mealInputs.push(temp);
                } else {
                    duplicates += 1;
            }
        }
    }

    for(i=0; i < bolusWizardInputs.length; i++) {
      current = bolusWizardInputs[i];
      //console.log(bolusWizardInputs[i]);
      temp = {};
      temp.timestamp = current.timestamp;
      temp.carbs = current.carb_input;
      temp.bwCarbs = current.carb_input;
      temp.id = current.id;

      // don't enter the treatment if there's another treatment with the same exact timestamp
      // to prevent duped carb entries from multiple sources
      if (!arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"carbs",current.id)) {
          if (arrayHasElementWithSameTimestampAndProperty(mealInputs,current.timestamp,"bolus",current.id)) {
              mealInputs.push(temp);
              //bwCarbs += temp.carbs;
          } else {
              console.error("Skipping bolus wizard entry", i, "in the pump history with",current.carb_input,"g carbs and no insulin.");
              if (current.carb_input === 0) {
                console.error("This is caused by a BolusWizard without carbs. If you specified insulin, it will be noted as a seperate Bolus");
              }
              if (current.timestamp) {
                  console.error("Timestamp of bolus wizard:", current.timestamp);
              }
          }
      } else {
          duplicates += 1;
      }
    }
    //if (duplicates > 0) console.error("Removed duplicate bolus/carb entries:" + duplicates);

    return mealInputs;
}

exports = module.exports = findMealInputs;
