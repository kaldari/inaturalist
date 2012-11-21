$(document).ready(function() {
  $('#fileupload').fileupload({
      url: '/observations/photo.json',
      maxFileSize: 5000000,
      limitConcurrentUploads: 2,
      acceptFileTypes: /(\.|\/)(gif|jpe?g|png)$/i,
      process: [
          {
              action: 'load',
              fileTypes: /^image\/(gif|jpeg|png)$/,
              maxFileSize: 20000000 // 20MB
          },
          {
              action: 'save'
          }
      ],
      add: function(e, data) {
        $(this).fileupload('process', data).done(function () {
          addFile(data)
          data.submit()
        })
      },
      // start: function(e) {
      //   console.log("[DEBUG] start e: ", e)
      // },
      submit: function(e, data) {
        if ($('.id_please_field input:checked', data.context).length == 0) {
          var params = $(':input', data.context).not('.id_please_field input:visible').serializeArray()
        } else {
          var params = $(':input', data.context).not('.id_please_field input[type=hidden]').serializeArray()
        }
        data.formData = params
        $(data.context).addClass('uploading')
        $(data.context).loadingShades('Uploading...')
      },
      fail: function(e, data) {
        alert('Upload failed: ' + data.errorThrown)
      },
      always: function(e, data) {
        $(data.context).shades('close')
        $(data.context).removeClass('uploading')
      },
      done: function(e, data) {
        var json = data.jqXHR.responseJSON || jQuery.parseJSON(data.jqXHR.responseText)
        var obs = json[0]
        if (obs.taxon) {
          $.fn.simpleTaxonSelector.selectTaxon($('.species_guess_field input', data.context), obs.taxon)
        }
        $(data.context).data('observation', obs)
        $('.description_field textarea', data.context).val(obs.description)
        $('.latitude_field input', data.context).val(obs.latitude).change()
        $('.longitude_field input', data.context).val(obs.longitude).change()
        $('.observed_on_string_field input', data.context).val(obs.observed_on_string)
        
        $('.uploadbutton', data.context).hide()
        // $('.removebutton', data.context).hide()
        $('.savebutton', data.context).show()
        $('.deletebutton', data.context).show()
        $('.deletebutton', data.context).after(
          $('<a target="_blank" class="readmore inter">View observation</a>').attr('href', '/observations/'+obs.id)
        )
      }
  })
})

function addFile(data) {
  var file = data.files[0]
  var wrapper = $('.observation.template:first').clone().removeClass('template')
  $('#fileupload .observations').append(wrapper)
  data.context = wrapper
  wrapper.data('filedata', data)
  $('.uploadbutton', wrapper).click(function() {
    $(this).parents('.observation').data('filedata').submit()
    return false
  })
  wrapper.fadeIn()
  $('.species_guess_field input:first', wrapper).simpleTaxonSelector({
    taxonIDField: $('input[name*=taxon_id]:first', wrapper)
  })
  $('.observed_on_string_field input:first', wrapper).iNatDatepicker()
  $('.place_guess_field input.text:first', wrapper).latLonSelector()
  loadImage(file, function(img) {
    $('.photocol', wrapper).append(img)
  }, {
    maxWidth: $('.photocol').width()
  })
}

$('.observation .savebutton').live('click', function() {
  var container = $(this).parents('.observation:first'),
      observation = container.data('observation')
  if ($('.id_please_field input:checked', container).length == 0) {
    var params = $(':input', container).not('.id_please_field input:visible').serialize()
  } else {
    var params = $(':input', container).not('.id_please_field input[type=hidden]').serialize()
  }
  if (observation) {
    var url = '/observations/'+observation.id,
        method = 'PUT'
  } else {
    var url = '/observations',
        method = 'POST'
  }
  $.ajax(url, {
    type: method,
    data: params,
    dataType: 'json',
    beforeSend: function() {
      container.loadingShades('Saving...')
    }
  }).done(function(data) {
  }).always(function() {
    container.shades('close')
  })
  return false
})
$('.observation .deletebutton').live('click', function() {
  if (!confirm('Are you sure you want to delete this observation?')) {
    return false
  }
  var container = $(this).parents('.observation:first'),
      data = container.find(':input').serialize(),
      observation = container.data('observation')
  if (!observation) {
    alert("Can't delete an observation that hasn't be saved.")
    return false
  }
  $.ajax('/observations/'+observation.id, {
    type: 'DELETE',
    data: data,
    dataType: 'json',
    beforeSend: function() {
      container.loadingShades('Deleting...')
    }
  }).done(function(data) {
    container.slideUp(function() { 
      $(this).remove()
    })
  }).fail(function(xhr, status) {
    if (xhr.statusText == 'OK') {
      container.slideUp(function() { 
        $(this).remove()
      })
    } else {
      alert('Failed to delete: ' + xhr.responseText)
    }
  }).always(function() {
    container.shades('close')
  })
  return false
})
